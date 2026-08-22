import 'dart:async';

import 'package:noise_alert/flights/lookup.dart';
import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/where/location.dart';

/// Keeps the live map live.
///
/// The polling used to begin when the recorder armed and end when it disarmed,
/// which made the map a by-product of a recording. Discard one, leave the tab,
/// or come back from another app, and the aircraft on screen froze where they
/// were, with nothing to say they had. The sky over the house does not stop
/// being interesting because a recording was thrown away, so the lifecycle
/// lives here instead and nothing in the capture path may touch it.
///
/// This is not a second source of traffic. It drives the same poll the matcher
/// reads out of, so putting the map on screen still costs a donated feed
/// nothing beyond what a recording would have cost anyway.
class SkyWatch {
  SkyWatch({
    required this.lookup,
    required this.location,
    this.refixInterval = const Duration(minutes: 2),
    this.tick = const Duration(seconds: 20),
  });

  final FlightLookupService lookup;
  final LocationService location;

  /// How often to ask the receiver where the phone is now.
  ///
  /// The centre only has to be roughly right: the query covers 25 nm and the
  /// map draws a few kilometres out of the middle of it, so walking to the end
  /// of the road changes nothing. Two minutes follows somebody on the move
  /// without holding the receiver awake.
  final Duration refixInterval;

  /// How often to check whether anything needs doing. Short, because one of
  /// the things it checks is whether the poll is still running.
  final Duration tick;

  /// Far enough to be worth re-centring the query on.
  static const double recentreM = 2000;

  Timer? _timer;
  bool _wanted = false;
  bool _fixing = false;
  DateTime? _fixedAt;

  SnapLocation? _observer;
  final StreamController<SnapLocation> _observers =
      StreamController<SnapLocation>.broadcast();

  /// Where the map is drawn from and where the query is centred, or null until
  /// the first fix of the session.
  SnapLocation? get observer => _observer;

  /// Emits every time the fix is renewed, so a screen can follow it without
  /// holding a copy taken at the moment it happened to be built. That copy is
  /// what used to leave the map behind after a discard.
  Stream<SnapLocation> get observerStream => _observers.stream;

  bool get isWatching => _timer != null;

  /// Begins, and keeps going. Safe to call repeatedly: the app calls it on
  /// every resume precisely so that a poll stopped by anything at all comes
  /// back within one [tick].
  void start() {
    _wanted = true;
    unawaited(_refresh());
    _timer ??= Timer.periodic(tick, (_) => unawaited(_refresh()));
  }

  /// Only for leaving the app. A backgrounded app has no map on screen and no
  /// business holding a donated feed open. Nothing in the recording path calls
  /// this, deliberately.
  void stop() {
    _wanted = false;
    _timer?.cancel();
    _timer = null;
    lookup.stopTracking();
  }

  /// A fix somebody else has already paid for, normally the one taken at the
  /// moment of a capture.
  ///
  /// Cheaper than asking the receiver twice, and it keeps the map and the
  /// complaint centred on the same spot rather than on two fixes taken seconds
  /// apart.
  void offer(SnapLocation fix) {
    if (_wanted) _adopt(fix);
  }

  Future<void> _refresh() async {
    if (!_wanted || _fixing) return;

    final DateTime? last = _fixedAt;
    final bool due = last == null ||
        DateTime.now().difference(last) >= refixInterval ||
        // The self-healing clause. Whatever stopped the poll, and whether or
        // not this file ever learns what it was, the map is live again inside
        // one tick.
        !lookup.isTracking;
    if (!due) return;

    _fixing = true;
    try {
      // Never asks for the permission, only reads it. The record screen is the
      // one place that puts a location dialog in front of the user, and a map
      // quietly raising a second one from behind it is how a Deny happens.
      final LocationStatus status = await location.check();
      if (!status.isReady) {
        // An older fix is still better than a blank map: the user has not
        // teleported, and the aircraft overhead are the point.
        final SnapLocation? known = status.lastFix;
        if (known != null && _observer == null) _adopt(known);
        return;
      }
      _adopt(await location.current());
    } on Object {
      // No fix this time. If there has never been one the screen says so; if
      // there has, the polling carries on from where it was.
      final SnapLocation? held = _observer;
      if (held != null && !lookup.isTracking) {
        lookup.startTracking(
          latitude: held.latitude,
          longitude: held.longitude,
        );
      }
    } finally {
      _fixing = false;
    }
  }

  void _adopt(SnapLocation fix) {
    final SnapLocation? was = _observer;
    _observer = fix;
    _fixedAt = DateTime.now();
    if (!_observers.isClosed) _observers.add(fix);

    final bool moved = was == null ||
        haversineMetres(
              was.latitude,
              was.longitude,
              fix.latitude,
              fix.longitude,
            ) >
            recentreM;
    if (moved || !lookup.isTracking) {
      lookup.startTracking(latitude: fix.latitude, longitude: fix.longitude);
    }
  }

  void dispose() {
    stop();
    unawaited(_observers.close());
  }
}
