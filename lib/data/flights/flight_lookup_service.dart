import 'dart:async';

import '../../core/constants.dart';
import '../../domain/aircraft.dart';
import '../../domain/flight_match.dart';
import 'adsb_source.dart';
import 'flight_matcher.dart';
import 'opensky_source.dart';

/// Keeps a short rolling history of nearby aircraft and turns a snap into a
/// ranked list of candidates.
///
/// The rolling cache is the point. A single query at the moment of the press
/// only gives positions *now*, so closest approach has to be dead-reckoned;
/// with a few seconds of real track history the geometry is observed rather
/// than guessed, and the confidence figure reflects that.
class FlightLookupService {
  FlightLookupService({
    required this.liveSources,
    this.openSky,
    this.matcher = const FlightMatcher(),
    this.historyRetention = const Duration(minutes: 5),
  });

  /// Tried in order; the first that answers wins. The others are not queried,
  /// to stay inside the community feeds' one-request-per-second etiquette.
  final List<AdsbSource> liveSources;

  final OpenSkySource? openSky;
  final FlightMatcher matcher;
  final Duration historyRetention;

  final Map<String, List<AircraftSample>> _tracks =
      <String, List<AircraftSample>>{};
  Timer? _pollTimer;
  bool _pollInFlight = false;

  final StreamController<List<AircraftTrack>> _trackController =
      StreamController<List<AircraftTrack>>.broadcast();

  String? _lastError;
  String? get lastError => _lastError;

  bool get isTracking => _pollTimer != null;

  int get trackedAircraftCount => _tracks.length;

  /// What the cache holds right now, oldest position first within each track.
  ///
  /// This is the live map's whole data source, and it costs nothing: the polls
  /// are already running for the matcher, and drawing them is only a second
  /// reader of the same cache. A map that fired its own queries would double
  /// the traffic to a donated feed to show the same aeroplanes.
  List<AircraftTrack> get tracks {
    final List<AircraftTrack> out = <AircraftTrack>[];
    for (final List<AircraftSample> track in _tracks.values) {
      if (track.isEmpty) continue;
      out.add(
        AircraftTrack(
          latest: track.last,
          points: track.map(TrackPoint.of).toList(growable: false),
        ),
      );
    }
    return out;
  }

  /// Emits after every poll that changed the cache. Broadcast, because the
  /// record screen's map and anything else watching are both readers.
  Stream<List<AircraftTrack>> get trackStream => _trackController.stream;

  /// Begins polling around a fixed point. Call when the snap screen opens.
  void startTracking({required double latitude, required double longitude}) {
    stopTracking();
    unawaited(_poll(latitude, longitude));
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: MatchConfig.trackPollIntervalMs),
      (_) => unawaited(_poll(latitude, longitude)),
    );
  }

  void stopTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void clear() {
    _tracks.clear();
    _emit();
  }

  void _emit() {
    if (_trackController.isClosed) return;
    _trackController.add(tracks);
  }

  Future<void> _poll(double latitude, double longitude) async {
    if (_pollInFlight) return;
    _pollInFlight = true;
    try {
      final List<AircraftSample> samples =
          await _queryLive(latitude, longitude);
      _ingest(samples);
      _lastError = null;
    } on Object catch (e) {
      // A dropped poll is not worth surfacing; the next one is three seconds
      // away. Only the message is kept, for the diagnostics line in Settings.
      _lastError = e.toString();
    } finally {
      _pollInFlight = false;
    }
  }

  Future<List<AircraftSample>> _queryLive(
      double latitude, double longitude) async {
    Object? lastFailure;
    for (final AdsbSource source in liveSources) {
      try {
        return await source.nearby(
          latitude: latitude,
          longitude: longitude,
          radiusNm: MatchConfig.queryRadiusNm,
        );
      } on Object catch (e) {
        lastFailure = e;
      }
    }
    throw AdsbException('all sources', 'No live source answered: $lastFailure');
  }

  void _ingest(List<AircraftSample> samples) {
    for (final AircraftSample s in samples) {
      final List<AircraftSample> track =
          _tracks.putIfAbsent(s.icao24, () => <AircraftSample>[]);
      // Position reports repeat between polls; only keep genuinely new ones.
      final bool duplicate = track.isNotEmpty &&
          track.last.timestamp.difference(s.timestamp).abs() <
              const Duration(milliseconds: 500);
      if (!duplicate) track.add(s);
    }
    _prune();
    _emit();
  }

  void _prune() {
    final DateTime cutoff = DateTime.now().toUtc().subtract(historyRetention);
    _tracks.removeWhere((String _, List<AircraftSample> track) {
      track.removeWhere(
          (AircraftSample s) => s.timestamp.toUtc().isBefore(cutoff));
      return track.isEmpty;
    });
  }

  List<AircraftSample> _cachedSamplesFor(DateTime heardAt) {
    final DateTime from = heardAt.subtract(
      Duration(seconds: MatchConfig.searchBackSeconds.round() + 30),
    );
    final DateTime to = heardAt.add(
      Duration(seconds: MatchConfig.searchForwardSeconds.round() + 30),
    );
    final List<AircraftSample> out = <AircraftSample>[];
    for (final List<AircraftSample> track in _tracks.values) {
      for (final AircraftSample s in track) {
        if (s.timestamp.isAfter(from) && s.timestamp.isBefore(to)) out.add(s);
      }
    }
    return out;
  }

  /// Resolves a snap using whatever the cache holds plus one fresh query.
  Future<FlightMatch> resolve({
    required Observer observer,
    required DateTime heardAt,
  }) async {
    final List<AircraftSample> samples = _cachedSamplesFor(heardAt);

    try {
      final List<AircraftSample> fresh =
          await _queryLive(observer.latitude, observer.longitude);
      _ingest(fresh);
      samples.addAll(fresh);
    } on Object catch (e) {
      _lastError = e.toString();
      if (samples.isEmpty) {
        return FlightMatch.none(
          searchedFrom: heardAt.subtract(
            Duration(seconds: MatchConfig.searchBackSeconds.round()),
          ),
          searchedTo: heardAt.add(
            Duration(seconds: MatchConfig.searchForwardSeconds.round()),
          ),
          note: 'Could not reach a flight data source. The snap is saved. '
              'Retry the lookup within the hour and OpenSky can still fill it in.',
        );
      }
    }

    return matcher.match(
        observer: observer, heardAt: heardAt, samples: samples);
  }

  /// Retrospective lookup for a snap taken offline. Free OpenSky access only
  /// reaches one hour back.
  Future<FlightMatch> backfill({
    required Observer observer,
    required DateTime heardAt,
  }) async {
    final OpenSkySource? sky = openSky;
    final DateTime from = heardAt.subtract(
      Duration(seconds: MatchConfig.searchBackSeconds.round()),
    );
    final DateTime to = heardAt.add(
      Duration(seconds: MatchConfig.searchForwardSeconds.round()),
    );

    if (sky == null || !sky.isConfigured) {
      return FlightMatch.none(
        searchedFrom: from,
        searchedTo: to,
        // Say what is actually wrong. "Nothing found" reads as "no aircraft
        // was there", which is a different and much more discouraging claim
        // than "this app cannot see into the past without an account".
        note: 'This recording is in the past, and live flight feeds only show '
            'aircraft that are in the sky right now. Looking up a past event '
            'needs OpenSky history. Add OpenSky API credentials in Settings, '
            'within an hour of the recording.',
      );
    }

    // Two probes across the window give the matcher a real track to work with
    // rather than a single point to extrapolate from.
    final List<AircraftSample> samples = <AircraftSample>[];
    for (final DateTime t in <DateTime>[
      heardAt.subtract(const Duration(seconds: 20)),
      heardAt,
    ]) {
      try {
        samples.addAll(
          await sky.historical(
            latitude: observer.latitude,
            longitude: observer.longitude,
            radiusNm: MatchConfig.queryRadiusNm,
            at: t,
          ),
        );
      } on AdsbException catch (e) {
        return FlightMatch.none(
            searchedFrom: from, searchedTo: to, note: e.message);
      }
    }

    return matcher.match(
        observer: observer, heardAt: heardAt, samples: samples);
  }

  void dispose() {
    stopTracking();
    unawaited(_trackController.close());
  }
}
