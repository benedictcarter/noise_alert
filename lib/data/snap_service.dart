import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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

  LocationStatus _locationStatus =
      const LocationStatus(LocationAvailability.denied);

  /// What the location layer could do at the last check. The snap screen shows
  /// this before the button is pressed, so a missing permission is a thing the
  /// user fixes in advance rather than discovers afterwards.
  LocationStatus get locationStatus => _locationStatus;

  /// Re-checks without prompting. Called on resume, so returning from system
  /// settings updates the screen.
  Future<LocationStatus> refreshLocationStatus() async {
    _locationStatus = await location.check();
    return _locationStatus;
  }

  Future<void> openLocationSettings() =>
      location.openRelevantSettings(_locationStatus.availability);

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

    // Ask for location now, not at the moment of the press. A permission
    // dialog appearing after the button press costs the user the seconds
    // during which the aircraft is still overhead.
    try {
      _locationStatus = await location.request();
    } on Object {
      _locationStatus = const LocationStatus(LocationAvailability.denied);
    }

    // Best-effort: the last known fix is good enough to aim the ADS-B query,
    // and waiting for a fresh one would leave the track cache empty for the
    // first several seconds.
    final SnapLocation? seed = _locationStatus.lastFix;
    if (seed != null) {
      lookup.startTracking(latitude: seed.latitude, longitude: seed.longitude);
    }
  }

  /// Stops waiting for the rest of the post-roll and saves what is recorded.
  /// Safe at any point: outside a capture it does nothing.
  void finishCaptureEarly() => recorder.cutCaptureShort();

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
    recorder.prepareCapture();

    // The fix is fetched *alongside* the post-roll rather than before it. A
    // cold receiver can take ten seconds, and there is no reason to spend them
    // standing still: the press is already timestamped, the microphone is
    // already running, and the aircraft is already leaving. Serialising the
    // two used to add the whole GPS wait to every capture.
    final Future<SnapLocation?> pendingFix = _bestEffortLocation();

    _emit(
      CaptureStage.recording,
      'Recording the tail of the event (${AudioConfig.postRollSeconds} s)…',
    );
    final EventWindow window = await recorder.captureEventWindow(pressedAt);
    final Float64List samples = window.samples;

    _emit(CaptureStage.locating);
    final SnapLocation? fix = await pendingFix;

    _emit(CaptureStage.analysing);
    // The ambient window can only be as long as the pre-roll actually was. A
    // snap fired from the widget, or seconds after opening the app, has less
    // than the full 30 s — the analyzer returns a null background rather than
    // measuring one out of audio that does not exist.
    final int ambientSamples = math.min(
      (AudioConfig.ambientWindowSeconds * AudioConfig.sampleRate).round(),
      window.preRollSamples,
    );
    final AcousticMetrics metrics = analyzer.analyze(
      samples: samples,
      sampleRate: AudioConfig.sampleRate.toDouble(),
      calibrationOffsetDb: settings.calibrationOffsetDb,
      calibrated: settings.calibrated,
      ambientSampleCount: ambientSamples,
      peakWindowSeconds: AudioConfig.clipSeconds.toDouble(),
      preRollSeconds: window.preRollSeconds,
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
      latitude: fix?.latitude,
      longitude: fix?.longitude,
      gpsAccuracyM: fix?.accuracyM,
      gpsAltitudeM: fix?.altitudeM,
      staleFix: fix?.stale ?? false,
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
      _emit(
        CaptureStage.done,
        'Saved without a location fix — ${_locationStatus.isReady ? 'the '
            'receiver did not report a position in time' : _locationStatus
            .message} No flight lookup is possible without one.',
      );
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
    if (!snap.hasLocation) {
      // Searching from a guessed position is worse than not searching: the
      // matcher would happily name an aircraft that was 5,000 km away.
      final Snap unlocated = snap.copyWith(
        match: FlightMatch.none(
          searchedFrom: snap.recordedAt,
          searchedTo: snap.recordedAt,
          note: 'No location was recorded for this snap, so the aircraft '
              'cannot be identified.',
        ),
        status: SnapStatus.unmatched,
      );
      await database.upsertSnap(unlocated);
      return unlocated;
    }

    final Observer observer = Observer(
      latitude: snap.latitude!,
      longitude: snap.longitude!,
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
        timeout: const Duration(seconds: 12),
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

      // Support directory, *not* the documents directory. On Android
      // path_provider maps documents to `<data>/app_flutter`, which is outside
      // every root flutter_email_sender's FileProvider declares
      // (`files-path`, `cache-path`, `external-path`). Attaching a clip from
      // there makes FileProvider.getUriForFile throw, the send fails, and the
      // user gets a mangled mailto: fallback with no attachment. Support maps
      // to `<data>/files`, which the provider can serve.
      final Directory dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'clips'),
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
