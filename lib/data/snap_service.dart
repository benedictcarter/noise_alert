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
import 'chart/chart_image_service.dart';
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
/// Thrown when a recording nobody asked for is discarded.
///
/// Not an error: the caller catches it and says nothing, because from the
/// user's point of view nothing happened.
class CaptureAbandoned implements Exception {
  const CaptureAbandoned();

  @override
  String toString() => 'The recording was discarded before it was saved.';
}

/// What came of a STOP & SEND.
///
/// Either the letter is open in the user's mail app, or the aircraft was
/// ambiguous enough that the button quietly became STOP & SAVE and the review
/// screen has to be shown.
class CaptureSendResult {
  const CaptureSendResult({required this.snap, this.outcome});

  final Snap snap;

  /// Null when the send was deliberately not attempted.
  final MailOutcome? outcome;

  bool get needsReview => outcome == null;
}

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
    this.chartImages = const ChartImageService(),
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
  final ChartImageService chartImages;

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
    // Wait out a disarm that is still unwinding. Without this the two overlap
    // and leave the microphone shut: disarm() clears _armed synchronously and
    // only then awaits recorder.stop(), so an arm() arriving in between sees
    // "not armed", calls recorder.start(), which returns immediately because
    // the old subscription is technically still alive -- and then the pending
    // stop() cancels it. The service believes it is armed and the microphone
    // is off. That is the widget path exactly: the app is backgrounded (paused
    // -> disarm), the widget is tapped, the app resumes and arms, and the
    // recording that follows contains nothing at all.
    await _transition;
    if (_armed) return;

    final Future<void> arming = _arm(settings);
    _transition = arming;
    try {
      await arming;
    } finally {
      if (identical(_transition, arming)) _transition = null;
    }
  }

  /// Serialises [arm] against [disarm]; see the note in [arm].
  Future<void>? _transition;

  Future<void> _arm(AppSettings settings) async {
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

  /// Ends the recording and saves it. The user's STOP.
  /// Safe at any point: outside a capture it does nothing.
  void finishCaptureEarly() => recorder.stopEventCapture();

  /// Ends the recording and throws it away.
  ///
  /// Only ever used for a recording the user did not ask for. The app opens
  /// recording, which is right for the case it is built around -- something is
  /// overhead now -- but wrong the moment the user walks off to Settings: a
  /// snap they never pressed for, and a clip of their kitchen, should not be
  /// waiting for them when they come back. Nothing is written to disk before
  /// the check, so abandoning really does leave no trace.
  void abandonCapture() {
    _abandoned = true;
    recorder.stopEventCapture();
  }

  bool _abandoned = false;

  /// Seconds recorded so far, for the running clock on the button.
  double get eventSeconds => recorder.eventSeconds;

  Future<void> disarm() async {
    await _transition;
    _armed = false;
    lookup.stopTracking();

    final Future<void> disarming = recorder.stop();
    _transition = disarming;
    try {
      await disarming;
    } finally {
      if (identical(_transition, disarming)) _transition = null;
    }
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
    _abandoned = false;

    // Last line of defence. Opening an event on a stopped microphone records
    // silence for as long as the user cares to hold the phone up, so if the
    // stream is not live, spend the moment it takes to start it. The press is
    // already timestamped, so the complaint still says when the aircraft was
    // heard; only the first fraction of a second of audio is lost, which is a
    // far better trade than the whole recording.
    if (!recorder.isRunning) {
      try {
        await recorder.start();
      } on Object {
        // No microphone, then. The capture continues regardless and the
        // complaint goes out without a sound level.
      }
    }

    // Synchronous, and first: the recording has to begin at the press, so
    // nothing may be awaited between here and opening the event.
    recorder.startEventCapture();

    // The fix is fetched *alongside* the recording rather than before it. A
    // cold receiver can take ten seconds, and there is no reason to spend them
    // standing still: the press is already timestamped, the microphone is
    // already running, and the aircraft is already leaving. Serialising the
    // two used to add the whole GPS wait to every capture.
    final Future<SnapLocation?> pendingFix = _bestEffortLocation();

    _emit(CaptureStage.recording, 'Recording — press STOP when it has passed.');
    final EventWindow window = await recorder.awaitEventEnd();
    if (_abandoned) {
      _abandoned = false;
      _emit(CaptureStage.idle);
      throw const CaptureAbandoned();
    }
    final Int16List samples = window.samples;
    // What the microphone actually delivered, which is not always what was
    // asked for. Every duration and every filter below is derived from this
    // rather than from AudioConfig.sampleRate.
    final double sampleRate = window.sampleRate;

    _emit(CaptureStage.locating);
    final SnapLocation? fix = await pendingFix;

    _emit(CaptureStage.analysing);
    // The background can only be as long as the microphone had been listening.
    // A recording started from the widget, or seconds after opening the app,
    // has less than the full 30 s — the analyzer returns a null background
    // rather than measuring one out of audio that does not exist.
    final AcousticMetrics metrics = _measure(
      samples: samples,
      window: window,
      sampleRate: sampleRate,
      settings: settings,
    );

    final DeviceDescription device = await deviceInfo.describe();
    final String id = _idFor(pressedAt);

    // Always written. Whether it is *attached* is the user's decision, made on
    // the review screen with the clip in front of them; whether it exists is
    // not a question worth asking at capture time, when the audio is the one
    // thing that cannot be recovered afterwards.
    final String? clipPath = metrics.hasMeasurement
        ? await _writeClip(
            id: id,
            samples: samples,
            metrics: metrics,
            sampleRate: sampleRate,
          )
        : null;

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
            .message} The complaint can still be sent from your home address; '
        'it just cannot name a flight.',
      );
      return snap;
    }

    _emit(CaptureStage.matching);
    snap = await resolveMatch(snap);
    _emit(CaptureStage.done);
    return snap;
  }

  /// The acoustics, or an honest blank where they should have been.
  ///
  /// Everything in here is best-effort by design. The microphone can be held by
  /// another app, muted by the OS, or simply deliver nothing; the analyzer can
  /// be handed a window too short to measure. None of that is a reason to throw
  /// away a complaint the user has already decided to make, so every failure
  /// path ends in [AcousticMetrics.unmeasured] with the reason attached rather
  /// than in an exception.
  AcousticMetrics _measure({
    required Int16List samples,
    required EventWindow window,
    required double sampleRate,
    required AppSettings settings,
  }) {
    if (window.isEmpty || sampleRate <= 0) {
      return const AcousticMetrics.unmeasured(
        note: 'The microphone delivered no audio for this recording.',
      );
    }

    // The background now comes out of the recording itself — the quiet
    // stretches either side of the flyover. The pre-roll is passed anyway as a
    // fallback for a recording stopped too soon to contain one.
    final Float64List ambient = window.ambient;
    final int ambientWanted =
        (AudioConfig.ambientWindowSeconds * sampleRate).round();

    try {
      return analyzer.analyzeSource(
        samples: Pcm16Samples(samples),
        sampleRate: sampleRate,
        // The most recent slice of the pre-roll, not the oldest: the street a
        // few seconds before the aircraft is the fairest comparison.
        ambient: FloatSamples(
          ambient.length > ambientWanted
              ? Float64List.sublistView(ambient, ambient.length - ambientWanted)
              : ambient,
        ),
        peakWindowSeconds: AudioConfig.clipSeconds.toDouble(),
        preRollSeconds: 0,
      );
    } on Object catch (e) {
      return AcousticMetrics.unmeasured(
        note: 'The recording could not be analysed ($e).',
      );
    }
  }

  /// Names the best candidate outright when it was plainly overhead.
  ///
  /// Ben's call, and it overrides the older rule that no flight is ever named
  /// without a tap: within [MatchConfig.autoConfirmMaxHorizontalM] of the
  /// observer there is nothing to adjudicate, and the click costs more than it
  /// buys. Beyond that the choice goes back to the user, because a candidate
  /// out on the ground track is exactly the case where the matcher can pick the
  /// wrong aircraft. The letter says either way that the identification is the
  /// closest ADS-B match and has not been independently verified.
  static Snap autoConfirm(Snap snap) {
    final FlightCandidate? best = snap.match?.best;
    if (best == null) return snap;
    if (best.horizontalRangeM > MatchConfig.autoConfirmMaxHorizontalM) {
      return snap;
    }
    return snap.copyWith(
      selectedIcao24: best.aircraft.icao24,
      status: SnapStatus.confirmed,
    );
  }

  /// STOP & SEND: capture, decide the aircraft question, open the letter.
  ///
  /// The point of the button is that one press ends the recording and the next
  /// thing the user sees is their own mail app with a complaint in it. That is
  /// only honest when there is nothing left to ask them:
  ///
  ///  * an aircraft within [MatchConfig.autoConfirmMaxHorizontalM] is named;
  ///  * no candidates at all means there is nothing to choose between, so the
  ///    complaint goes out saying the aircraft was not identified — a letter
  ///    that says "an aircraft was audible at this address at this time" is
  ///    still a complaint, and is the whole point of the app;
  ///  * anything in between is a real question, so the button degrades to
  ///    STOP & SAVE and the caller shows the review screen.
  Future<CaptureSendResult> captureAndSend({
    required AppSettings settings,
    String notes = '',
  }) async =>
      sendCaptured(await capture(settings: settings, notes: notes));

  /// The second half of STOP & SEND, for a snap that has already been captured.
  ///
  /// Separate from [captureAndSend] because the UI cannot know which button
  /// will be pressed until the recording is already running: both buttons end
  /// the same capture, and only afterwards does it become a save or a send.
  Future<CaptureSendResult> sendCaptured(Snap captured) async {
    final Snap decided = autoConfirm(captured);

    if (decided.confirmedCandidate == null) {
      if (captured.match?.hasCandidates ?? false) {
        // Candidates, but none of them obviously overhead. This is the one
        // case worth a tap.
        return CaptureSendResult(snap: decided);
      }
      // Nothing was found, so there is nothing to confirm.
      final Snap unidentified = decided.copyWith(
        unidentifiedAircraft: true,
        status: SnapStatus.confirmed,
      );
      await database.upsertSnap(unidentified);
      return CaptureSendResult(
        snap: unidentified,
        outcome: await compose(unidentified),
      );
    }

    await database.upsertSnap(decided);
    return CaptureSendResult(snap: decided, outcome: await compose(decided));
  }

  /// Runs (or re-runs) the flight lookup for a snap and stores the result.
  ///
  /// Which source is asked depends entirely on how old the snap is. A live feed
  /// only ever reports aircraft that are in the sky *now*, so for anything
  /// older than the track cache holds, querying one cannot succeed -- the
  /// matcher correctly rejects every aircraft it returns, and the user is told
  /// "nothing found" when the truth is "nothing was asked". Past events go
  /// straight to the retrospective source instead.
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

    // Older than the rolling cache retains, so neither the cache nor a fresh
    // live query can hold anything from the moment in question.
    final Duration age = DateTime.now().difference(snap.recordedAt);
    final bool past = age > lookup.historyRetention;

    FlightMatch match;
    if (preferHistorical || past) {
      match =
          await lookup.backfill(observer: observer, heardAt: snap.recordedAt);
    } else {
      match =
          await lookup.resolve(observer: observer, heardAt: snap.recordedAt);
      if (match.candidates.isEmpty && age > const Duration(seconds: 30)) {
        final FlightMatch historical = await lookup.backfill(
            observer: observer, heardAt: snap.recordedAt);
        if (historical.candidates.isNotEmpty) match = historical;
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

  /// Records where the user says the worst of the flyover was.
  ///
  /// Pass null to go back to letting the measured maximum speak for itself.
  /// This never changes a measured figure: the clip was cut at capture time
  /// from the loudest slice and stays there, and the letter quotes the marked
  /// moment as the complainant's own account of it.
  Future<Snap> setMarkedPeak(Snap snap, int? millis) async {
    final Snap updated = snap.copyWith(
      markedPeakMs: millis,
      clearMarkedPeak: millis == null,
    );
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
    // Rendered fresh at send time rather than kept from the capture: it is
    // cheap to draw, and a chart regenerated from the stored trace can never
    // disagree with the numbers in the body of the letter.
    final ComplaintDraft draft = template.render(
      snap: snap,
      profile: profile,
      settings: settings,
      chartPath: await chartImages.renderForEmail(snap),
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
        chartPath: await chartImages.renderForEmail(snap),
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
    required Int16List samples,
    required AcousticMetrics metrics,
    required double sampleRate,
  }) async {
    try {
      final int start = ((metrics.peakWindowStartMs / 1000) * sampleRate)
          .round()
          .clamp(0, samples.length - 1);
      final int length =
          ((metrics.peakWindowDurationMs / 1000) * sampleRate).round();
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
        // Converted a slice at a time: a five-minute recording turned into
        // doubles in one go would cost four times what holding it as PCM16
        // costs, for the sake of the ten seconds actually being saved.
        samples: pcm16SliceToFloat(samples, start, end),
        sourceSampleRate: sampleRate,
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
