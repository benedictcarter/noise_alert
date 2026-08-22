import 'dart:math' as math;

import 'package:noise_alert/flights/config.dart';
import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';

/// Where the listener was standing.
class Observer {
  const Observer({
    required this.latitude,
    required this.longitude,
    this.altitudeM = 0,
  });

  final double latitude;
  final double longitude;

  /// Metres above mean sea level, from the GPS fix. Only used as the ground
  /// reference for computing height-above-observer, where its ±10 m noise is
  /// irrelevant against an aircraft several hundred metres up.
  final double altitudeM;
}

/// Decides which aircraft made the noise.
///
/// Two things make this harder than "what was overhead at time T":
///
///  1. Sound is slow. The aircraft that produced the sound you heard at time T
///     was at its closest approach `slant / 343` seconds earlier.
///  2. Humans are slower. The button press lands some seconds after the sound.
///
/// So the matcher searches a window, and for each candidate instant checks that
/// the sound leaving the aircraft *then* would plausibly have arrived at, or
/// shortly before, the moment the button was pressed.
class FlightMatcher {
  const FlightMatcher({
    this.maxReactionLag = const Duration(seconds: 30),
    this.clockTolerance = const Duration(seconds: 10),
    this.stepSeconds = 1.0,
  });

  /// How long after hearing the noise the user might realistically press.
  final Duration maxReactionLag;

  /// Slack for device clock skew and for a user who presses on approach.
  final Duration clockTolerance;

  final double stepSeconds;

  FlightMatch match({
    required Observer observer,
    required DateTime heardAt,
    required List<AircraftSample> samples,
  }) {
    final DateTime from = heardAt.subtract(
      Duration(milliseconds: (MatchConfig.searchBackSeconds * 1000).round()),
    );
    final DateTime to = heardAt.add(
      Duration(milliseconds: (MatchConfig.searchForwardSeconds * 1000).round()),
    );

    if (samples.isEmpty) {
      return FlightMatch.none(
        searchedFrom: from,
        searchedTo: to,
        note: 'No ADS-B traffic was reported nearby at the time.',
      );
    }

    final Map<String, List<AircraftSample>> byAircraft =
        <String, List<AircraftSample>>{};
    for (final AircraftSample s in samples) {
      byAircraft.putIfAbsent(s.icao24, () => <AircraftSample>[]).add(s);
    }

    final List<FlightCandidate> candidates = <FlightCandidate>[];
    for (final MapEntry<String, List<AircraftSample>> entry
        in byAircraft.entries) {
      final List<AircraftSample> track = List<AircraftSample>.of(entry.value)
        ..sort(
          (AircraftSample a, AircraftSample b) =>
              a.timestamp.compareTo(b.timestamp),
        );
      final FlightCandidate? c = _evaluate(
        observer: observer,
        heardAt: heardAt,
        from: from,
        to: to,
        track: track,
      );
      if (c != null) candidates.add(c);
    }

    candidates.sort(
        (FlightCandidate a, FlightCandidate b) => b.score.compareTo(a.score));

    if (candidates.isEmpty) {
      return FlightMatch.none(
        searchedFrom: from,
        searchedTo: to,
        note: 'Aircraft were nearby but none passed close or high enough '
            'overhead to be a plausible source.',
      );
    }

    return FlightMatch(
      candidates: candidates,
      confidence: _confidence(candidates),
      searchedFrom: from,
      searchedTo: to,
    );
  }

  FlightCandidate? _evaluate({
    required Observer observer,
    required DateTime heardAt,
    required DateTime from,
    required DateTime to,
    required List<AircraftSample> track,
  }) {
    final bool extrapolated = track.length < 2;

    double bestSlant = double.infinity;
    DateTime? bestTime;
    double bestHorizontal = 0;
    double bestHeight = 0;
    AircraftSample? bestNearestSample;

    final int steps =
        (to.difference(from).inMilliseconds / (stepSeconds * 1000)).ceil();
    for (int i = 0; i <= steps; i++) {
      final DateTime t = from.add(
        Duration(milliseconds: (i * stepSeconds * 1000).round()),
      );
      if (t.isAfter(to)) break;

      final AircraftSample? position = _positionAt(track, t);
      if (position == null) continue;
      if (position.onGround) continue;

      final double horizontal = haversineMetres(
        observer.latitude,
        observer.longitude,
        position.latitude,
        position.longitude,
      );
      final double height =
          ((position.altitudeFt ?? 0) / kFeetPerMetre) - observer.altitudeM;
      if (height <= 0) continue;

      final double slant = slantRangeMetres(horizontal, height);

      // Would the sound emitted at t have reached the observer by the time the
      // button was pressed, and not so long before that they would have
      // forgotten about it?
      final DateTime arrival = t.add(
          soundTravelTime(slant, speedOfSoundMs: MatchConfig.speedOfSoundMs));
      final Duration lag = heardAt.difference(arrival);
      if (lag > maxReactionLag) continue;
      if (lag < -clockTolerance) continue;

      if (slant < bestSlant) {
        bestSlant = slant;
        bestTime = t;
        bestHorizontal = horizontal;
        bestHeight = height;
        bestNearestSample = _nearestSample(track, t);
      }
    }

    if (bestTime == null || bestNearestSample == null) return null;

    final double elevation = elevationDegrees(bestHorizontal, bestHeight);
    if (bestSlant > MatchConfig.maxSlantRangeM) return null;
    if (elevation < MatchConfig.minElevationDegrees) return null;

    return FlightCandidate(
      aircraft: bestNearestSample,
      closestApproachTime: bestTime,
      slantRangeM: bestSlant,
      horizontalRangeM: bestHorizontal,
      heightAboveObserverM: bestHeight,
      elevationDegrees: elevation,
      score: _score(
        slantM: bestSlant,
        elevationDeg: elevation,
        extrapolated: extrapolated,
      ),
      extrapolated: extrapolated,
      // The observed path, kept so the map can draw where this aeroplane
      // actually went rather than the one point it happened to be at when the
      // geometry was best. Thinned, because a busy sky puts one of these on
      // every candidate and they all live in the same database row.
      track: decimateTrack(
        track.map(TrackPoint.of).toList(growable: false),
        MatchConfig.maxTrackPoints,
      ),
    );
  }

  /// Position at [t]: interpolated between bracketing reports where possible,
  /// otherwise dead-reckoned from the nearest one using its ground speed,
  /// track and vertical rate.
  AircraftSample? _positionAt(List<AircraftSample> track, DateTime t) {
    if (track.isEmpty) return null;

    for (int i = 0; i < track.length - 1; i++) {
      final AircraftSample a = track[i];
      final AircraftSample b = track[i + 1];
      if (!t.isBefore(a.timestamp) && !t.isAfter(b.timestamp)) {
        final double span =
            b.timestamp.difference(a.timestamp).inMicroseconds.toDouble();
        if (span <= 0) return a;
        final double f = t.difference(a.timestamp).inMicroseconds / span;
        return a.copyWith(
          timestamp: t,
          latitude: a.latitude + (b.latitude - a.latitude) * f,
          longitude: a.longitude + (b.longitude - a.longitude) * f,
          altitudeFt: a.altitudeFt == null || b.altitudeFt == null
              ? a.altitudeFt
              : a.altitudeFt! + (b.altitudeFt! - a.altitudeFt!) * f,
        );
      }
    }

    final AircraftSample anchor = _nearestSample(track, t);
    return _deadReckon(anchor, t);
  }

  AircraftSample _deadReckon(AircraftSample from, DateTime t) {
    final double dtSeconds = t.difference(from.timestamp).inMicroseconds / 1e6;
    final double? gs = from.groundSpeedKt;
    final double? trk = from.trackDeg;
    if (gs == null || trk == null || dtSeconds == 0) {
      return from.copyWith(timestamp: t);
    }

    final double distanceM = gs * kMetresPerNauticalMile / 3600.0 * dtSeconds;
    final ({double latitude, double longitude}) p = destinationPoint(
      from.latitude,
      from.longitude,
      trk,
      distanceM,
    );

    final double? vs = from.verticalRateFpm;
    final double? alt = from.altitudeFt;
    return from.copyWith(
      timestamp: t,
      latitude: p.latitude,
      longitude: p.longitude,
      altitudeFt:
          (alt != null && vs != null) ? alt + vs * dtSeconds / 60.0 : alt,
    );
  }

  AircraftSample _nearestSample(List<AircraftSample> track, DateTime t) {
    AircraftSample best = track.first;
    int bestDelta = (track.first.timestamp.difference(t).inMilliseconds).abs();
    for (final AircraftSample s in track.skip(1)) {
      final int d = (s.timestamp.difference(t).inMilliseconds).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = s;
      }
    }
    return best;
  }

  double _score({
    required double slantM,
    required double elevationDeg,
    required bool extrapolated,
  }) {
    // Proximity dominates: the inverse-square law means a plane twice as far
    // away is 6 dB quieter, and 6 dB is the difference between "that was loud"
    // and "I did not notice it".
    final double proximity = 1000.0 / (1000.0 + slantM);
    // Overhead beats off to one side at the same range: the ground attenuates
    // and screens shallow paths.
    final double overhead = 0.3 + 0.7 * math.sin(degToRad(elevationDeg));
    final double confidencePenalty = extrapolated ? 0.85 : 1.0;
    return proximity * overhead * confidencePenalty;
  }

  /// Conservative on purpose: this number gates whether the UI dares put a
  /// flight number in front of the user as the likely answer.
  double _confidence(List<FlightCandidate> ranked) {
    final FlightCandidate best = ranked.first;

    // Absolute geometry: a 400 m overhead pass is unambiguous, a 6 km one at
    // 15 degrees is a guess however few competitors it has.
    final double rangeQuality =
        (1.0 - (best.slantRangeM / 6000.0)).clamp(0.0, 1.0);
    final double elevationQuality =
        ((best.elevationDegrees - MatchConfig.minElevationDegrees) / 50.0)
            .clamp(0.0, 1.0);
    final double geometry = 0.6 * rangeQuality + 0.4 * elevationQuality;

    // Separation from the runner-up.
    double separation = 1.0;
    if (ranked.length > 1) {
      final double second = ranked[1].score;
      separation = best.score <= 0
          ? 0
          : ((best.score - second) / best.score).clamp(0.0, 1.0);
      // A clean win still needs a decent margin to count as "clear".
      separation = math.min(1.0, separation / 0.5);
    }

    double confidence = geometry * (0.55 + 0.45 * separation);
    if (best.extrapolated) confidence *= 0.85;
    return confidence.clamp(0.0, 1.0);
  }
}
