import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/device_info.dart';
import '../domain/acoustic_metrics.dart';
import '../domain/flight_match.dart';
import '../domain/profile.dart';
import '../domain/settings.dart';
import '../domain/snap.dart';
import 'audio/noise_analyzer.dart';
import 'audio/recorder_service.dart';
import 'audio/wav_writer.dart';
import 'flights/flight_lookup_service.dart';
import 'flights/flight_matcher.dart';
import 'location/location_service.dart';
import 'mail/complaint_template.dart';
import 'mail/mail_sender.dart';
import 'storage/database.dart';

/// What the snap screen needs to know while a capture is in progress.
enum CaptureStage { idle, locating, recording, analysing, matching, done }

class CaptureProgress {
  const CaptureProgress(this.stage, {this.message});

  final CaptureStage stage;
  final String? message;

  bool get isBusy => stage != CaptureStage.idle && stage != CaptureStage.done;
}

/// Ties the microphone, the GPS, the flight lookup and the database together
/// into the one thing the user actually asked for: a single button.
///
/// The ordering matters. The button press is timestamped *first* and everything
/// else is measured relative to that instant, because the press is the only
/// moment we know the user actually heard the aircraft. GPS and network waits
/// happen afterwards and must not shift the recording window.
class SnapService {
  SnapService({
    required this.database,
    required this.recorder,
    required this.lookup,
    required this.deviceInfo,
    this.location = const LocationService(),
    this.analyzer = const NoiseAnalyzer(),
    this.wavWriter =
        const WavWriter(clipSampleRate: AudioConfig.clipSampleRate),
    this.mailSender = const MailSender(),
    this.template = const ComplaintTemplate(),
  });

  final AppDatabase database;
  final RecorderService recorder;
  final FlightLookupService lookup;
  final DeviceInfoService deviceInfo;
  final LocationService location;
  final NoiseAnalyzer analyzer;
  final WavWriter wavWriter;
  final MailSender mailSender;
  final ComplaintTemplate template;

  final StreamController<CaptureProgress> _progress =
      StreamController<CaptureProgress>.broadcast();
  Stream<CaptureProgress> get progress => _progress.stream;

  bool _armed = false;
  bool get isArmed => _armed;

  /// Opens the microphone and starts polling for nearby aircraft.
  ///
  /// Called when the snap screen appears, not when the button is pressed: the
  /// pre-roll buffer and the aircraft track cache both need to already be
  /// running by the time the user reacts to a noise.
  Future<void> arm({required AppSettings settings}) async {
    if (_armed) return;
    recorder.calibrationOffsetDb = settings.calibrationOffsetDb;
    await recorder.start();
    _armed = true;

    // Best-effort: the last known fix is good enough to aim the ADS-B query,
    // and waiting for a fresh one would leave the track cache empty for the
    // first several seconds.
    try {
      final SnapLocation? seed = await location.lastKnown();
      if (seed != null) {
        lookup.startTracking(
            latitude: seed.latitude, longitude: seed.longitude);
      }
    } on Object {
      // No fix yet; capture() will query and start tracking then.
    }
  }

  Future<void> disarm() async {
    _armed = false;
    lookup.stopTracking();
    await recorder.stop();
  }

  /// The button.
  ///
  /// Returns as soon as the snap is saved. The flight match is resolved in the
  /// same call because the ADS-B query is fast, but a failure there never loses
  /// the capture: the snap is written to the database first.
  Future<Snap> capture({
    required AppSettings settings,
    String notes = '',
  }) async {
    final DateTime pressedAt = DateTime.now();

    _emit(CaptureStage.locating);
    final SnapLocation? fix = await _bestEffortLocation();

    _emit(
      CaptureStage.recording,
      'Recording the tail of the event (${AudioConfig.postRollSeconds} s)…',
    );
    final Float64List samples = await recorder.captureEventWindow(pressedAt);

    _emit(CaptureStage.analysing);
    final AcousticMetrics metrics = analyzer.analyze(
      samples: samples,
      sampleRate: AudioConfig.sampleRate.toDouble(),
      calibrationOffsetDb: settings.calibrationOffsetDb,
      calibrated: settings.calibrated,
      ambientSampleCount:
          (AudioConfig.ambientWindowSeconds * AudioConfig.sampleRate).round(),
      peakWindowSeconds: AudioConfig.clipSeconds.toDouble(),
    );

    final DeviceDescription device = await deviceInfo.describe();
    final String id = _idFor(pressedAt);

    String? clipPath;
    if (settings.keepClip) {
      clipPath = await _writeClip(id: id, samples: samples, metrics: metrics);
    }

    Snap snap = Snap(
      id: id,
      recordedAt: pressedAt,
      latitude: fix?.latitude ?? 0,
      longitude: fix?.longitude ?? 0,
      gpsAccuracyM: fix?.accuracyM,
      gpsAltitudeM: fix?.altitudeM,
      metrics: metrics,
      status: SnapStatus.unmatched,
      clipPath: clipPath,
      attachClip: clipPath != null && settings.attachClipByDefault,
      deviceModel: device.model,
      osVersion: device.osVersion,
      appVersion: device.appVersion,
      notes: notes,
    );
    await database.upsertSnap(snap);

    if (fix == null) {
      _emit(CaptureStage.done,
          'Saved without a location fix — no flight lookup.');
      return snap;
    }

    _emit(CaptureStage.matching);
    snap = await resolveMatch(snap);
    _emit(CaptureStage.done);
    return snap;
  }

  /// Runs (or re-runs) the flight lookup for a snap and stores the result.
  ///
  /// Live sources first; if they turn up nothing and the snap is still inside
  /// OpenSky's one-hour retrospective window, back-fill from there.
  Future<Snap> resolveMatch(Snap snap, {bool preferHistorical = false}) async {
    final Observer observer = Observer(
      latitude: snap.latitude,
      longitude: snap.longitude,
      altitudeM: snap.gpsAltitudeM ?? 0,
    );

    FlightMatch match;
    if (preferHistorical) {
      match =
          await lookup.backfill(observer: observer, heardAt: snap.recordedAt);
    } else {
      match =
          await lookup.resolve(observer: observer, heardAt: snap.recordedAt);
      if (match.candidates.isEmpty) {
        final Duration age = DateTime.now().difference(snap.recordedAt);
        if (age > const Duration(seconds: 30) &&
            age < const Duration(minutes: 55)) {
          final FlightMatch historical = await lookup.backfill(
              observer: observer, heardAt: snap.recordedAt);
          if (historical.candidates.isNotEmpty) match = historical;
        }
      }
    }

    final Snap updated = snap.copyWith(
      match: match,
      status: match.candidates.isEmpty
          ? SnapStatus.unmatched
          : SnapStatus.awaitingReview,
    );
    await database.upsertSnap(updated);
    return updated;
  }

  /// Records the user's decision about which aircraft it was.
  ///
  /// Passing null for [icao24] with [unidentified] true is a positive choice to
  /// complain without naming a flight — which is a legitimate complaint, and
  /// far better than guessing.
  Future<Snap> confirmAircraft(
    Snap snap, {
    String? icao24,
    bool unidentified = false,
  }) async {
    final Snap updated = snap.copyWith(
      selectedIcao24: icao24,
      clearSelection: icao24 == null,
      unidentifiedAircraft: unidentified,
      status: (icao24 != null || unidentified)
          ? SnapStatus.confirmed
          : SnapStatus.awaitingReview,
    );
    await database.upsertSnap(updated);
    return updated;
  }

  Future<Snap> setAttachClip(Snap snap, bool attach) async {
    final Snap updated = snap.copyWith(attachClip: attach);
    await database.upsertSnap(updated);
    return updated;
  }

  Future<Snap> setNotes(Snap snap, String notes) async {
    final Snap updated = snap.copyWith(notes: notes);
    await database.upsertSnap(updated);
    return updated;
  }

  /// Renders the complaint and opens the device mail composer.
  ///
  /// The snap is only marked sent once the composer actually opened. Neither
  /// platform reports whether the user pressed send, so "sent" here means
  /// "handed to your mail app" — the history screen says so in as many words.
  Future<MailOutcome> compose(Snap snap) async {
    if (!snap.isReadyToSend) {
      return const MailOutcome(
        MailResult.failed,
        detail:
            'Confirm which aircraft it was (or mark it unidentified) first.',
      );
    }

    final ComplainantProfile profile = await database.loadProfile();
    if (!profile.isComplete) {
      return const MailOutcome(
        MailResult.failed,
        detail: 'Fill in your name, address and email in Settings first.',
      );
    }

    final AppSettings settings = await database.loadSettings();
    final ComplaintDraft draft = template.render(
      snap: snap,
      profile: profile,
      settings: settings,
    );

    final MailOutcome outcome = await mailSender.send(draft);
    if (outcome.opened) {
      await database.upsertSnap(
        snap.copyWith(status: SnapStatus.sent, sentAt: DateTime.now()),
      );
    }
    return outcome;
  }

  /// Preview of the letter, for the review screen and the settings editor.
  Future<ComplaintDraft> preview(Snap snap) async => template.render(
        snap: snap,
        profile: await database.loadProfile(),
        settings: await database.loadSettings(),
      );

  Future<void> deleteSnap(Snap snap) async {
    final String? path = snap.clipPath;
    if (path != null) {
      try {
        final File file = File(path);
        if (file.existsSync()) await file.delete();
      } on Object {
        // A stranded clip is not worth failing the delete over.
      }
    }
    await database.deleteSnap(snap.id);
  }

  Future<void> dispose() async {
    await disarm();
    await _progress.close();
  }

  // --- internals ---------------------------------------------------------

  Future<SnapLocation?> _bestEffortLocation() async {
    try {
      final SnapLocation fix = await location.current(
        timeout: const Duration(seconds: 8),
      );
      if (!lookup.isTracking) {
        lookup.startTracking(latitude: fix.latitude, longitude: fix.longitude);
      }
      return fix;
    } on Object {
      // A stale fix beats no snap at all — the user is standing in their own
      // garden, and the previous fix is almost certainly the same garden.
      try {
        return await location.lastKnown();
      } on Object {
        return null;
      }
    }
  }

  /// Writes the loudest [AudioConfig.clipSeconds] of the event, not the first.
  Future<String?> _writeClip({
    required String id,
    required Float64List samples,
    required AcousticMetrics metrics,
  }) async {
    try {
      final int start =
          ((metrics.peakWindowStartMs / 1000) * AudioConfig.sampleRate)
              .round()
              .clamp(0, samples.length - 1);
      final int length =
          ((metrics.peakWindowDurationMs / 1000) * AudioConfig.sampleRate)
              .round();
      final int end = (start + length).clamp(0, samples.length);

      final Directory dir = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'clips'),
      );
      final File file = await wavWriter.write(
        path: p.join(dir.path, '$id.wav'),
        samples: Float64List.sublistView(samples, start, end),
        sourceSampleRate: AudioConfig.sampleRate.toDouble(),
      );
      return file.path;
    } on Object {
      // Losing the clip must never lose the measurement.
      return null;
    }
  }

  static String _idFor(DateTime time) =>
      time.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  void _emit(CaptureStage stage, [String? message]) {
    if (!_progress.isClosed) {
      _progress.add(CaptureProgress(stage, message: message));
    }
  }
}
