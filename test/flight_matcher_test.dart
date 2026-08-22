import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/flights/matcher.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';
import 'package:noise_alert/snap/snap.dart';

const Observer _home = Observer(latitude: 51.5000, longitude: -0.1000);

/// Metres per degree of longitude at the observer's latitude, near enough.
const double _mPerDegLon = 69300;
const double _mPerDegLat = 111320;

final DateTime _t0 = DateTime.utc(2026, 8, 19, 14, 30, 0);

/// A straight, level track passing [offsetM] north of the observer, at its
/// closest approach at [closestAt].
List<AircraftSample> _track({
  required String icao24,
  required DateTime closestAt,
  required double altitudeFt,
  double speedMs = 103, // ~200 kt
  double offsetM = 0,
  String? callsign,
  int fromSeconds = -25,
  int toSeconds = 10,
}) {
  final List<AircraftSample> out = <AircraftSample>[];
  for (int s = fromSeconds; s <= toSeconds; s++) {
    out.add(
      AircraftSample(
        icao24: icao24,
        timestamp: closestAt.add(Duration(seconds: s)),
        latitude: _home.latitude + offsetM / _mPerDegLat,
        longitude: _home.longitude + (s * speedMs) / _mPerDegLon,
        callsign: callsign,
        altitudeFt: altitudeFt,
        groundSpeedKt: speedMs * 1.94384,
        trackDeg: 90,
        source: 'test',
      ),
    );
  }
  return out;
}

void main() {
  const FlightMatcher matcher = FlightMatcher();

  test('no samples means no candidates and an explanatory note', () {
    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: _t0,
      samples: const <AircraftSample>[],
    );

    expect(match.candidates, isEmpty);
    expect(match.note, isNotNull);
    expect(match.isConfidentEnoughToPreselect, isFalse);
  });

  test('an aircraft overhead a few seconds before the press is matched', () {
    // 1,000 ft ≈ 305 m up: the sound took ~0.9 s to arrive, and the user
    // pressed about 5 s after hearing it.
    final DateTime heardAt = _t0.add(const Duration(seconds: 6));

    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: heardAt,
      samples: _track(
        icao24: 'abc123',
        closestAt: _t0,
        altitudeFt: 1000,
        callsign: 'BAW123',
      ),
    );

    expect(match.candidates, hasLength(1));
    final FlightCandidate best = match.best!;
    expect(best.aircraft.callsign, 'BAW123');
    expect(best.heightAboveObserverFt, closeTo(1000, 20));
    expect(best.elevationDegrees, greaterThan(80));

    // The closest approach is *before* the press, which is the entire point of
    // searching backwards rather than asking "what is overhead now".
    expect(best.closestApproachTime.isBefore(heardAt), isTrue);
    expect(
      heardAt.difference(best.closestApproachTime).inSeconds,
      inInclusiveRange(4, 8),
    );

    // One aircraft, right overhead, observed rather than extrapolated.
    expect(best.extrapolated, isFalse);
    expect(match.isConfidentEnoughToPreselect, isTrue);
  });

  test('an airliner in the cruise 40 km away is rejected, not offered', () {
    final DateTime heardAt = _t0.add(const Duration(seconds: 6));

    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: heardAt,
      samples: _track(
        icao24: 'ffff01',
        closestAt: _t0,
        altitudeFt: 35000,
        offsetM: 40000,
        callsign: 'HIGH01',
      ),
    );

    // 40 km out and 10 km up is well past the 12 km slant-range limit: it
    // cannot be what the user heard, and offering it would invite a complaint
    // about the wrong flight.
    expect(match.candidates, isEmpty);
  });

  test('the closer of two aircraft wins, and both stay on the list', () {
    final DateTime heardAt = _t0.add(const Duration(seconds: 6));

    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: heardAt,
      samples: <AircraftSample>[
        ..._track(
          icao24: 'aaa111',
          closestAt: _t0,
          altitudeFt: 900,
          callsign: 'LOW01',
        ),
        ..._track(
          icao24: 'bbb222',
          closestAt: _t0,
          altitudeFt: 4000,
          offsetM: 3000,
          callsign: 'MID02',
        ),
      ],
    );

    expect(match.candidates.length, 2);
    expect(match.best!.aircraft.callsign, 'LOW01');
    expect(
      match.candidates.first.slantRangeM,
      lessThan(match.candidates.last.slantRangeM),
    );
  });

  test('an aircraft that had already passed long before is out of the window',
      () {
    // Closest approach three minutes before the press: even a slow reaction
    // cannot stretch that far, and the sound would have arrived and gone.
    final DateTime heardAt = _t0.add(const Duration(minutes: 3));

    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: heardAt,
      samples: _track(icao24: 'ccc333', closestAt: _t0, altitudeFt: 1000),
    );

    expect(match.candidates, isEmpty);
  });

  test('a match round-trips through the database encoding', () {
    final FlightMatch match = matcher.match(
      observer: _home,
      heardAt: _t0.add(const Duration(seconds: 6)),
      samples: _track(
        icao24: 'abc123',
        closestAt: _t0,
        altitudeFt: 1000,
        callsign: 'BAW123',
      ),
    );

    final FlightMatch back = decodeMatch(encodeMatch(match));

    expect(back.candidates.length, match.candidates.length);
    expect(back.best!.aircraft.icao24, match.best!.aircraft.icao24);
    expect(back.best!.slantRangeM, closeTo(match.best!.slantRangeM, 0.001));
    expect(back.confidence, closeTo(match.confidence, 0.001));
  });
}
