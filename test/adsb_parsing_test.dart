import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/core/geo.dart';
import 'package:noise_alert/data/flights/adsb_source.dart';
import 'package:noise_alert/data/flights/opensky_source.dart';
import 'package:noise_alert/data/flights/tar1090_source.dart';
import 'package:noise_alert/domain/aircraft.dart';

/// Shaped after a real adsb.lol `/v2/point` response, trimmed to the fields
/// the matcher reads. Kept as a literal string so it exercises the JSON path
/// end to end rather than starting from a decoded map.
const String _tar1090Body = '''
{
  "ac": [
    {
      "hex": "4CA2D1",
      "type": "adsb_icao",
      "flight": "RYR8452 ",
      "r": "EI-DYH",
      "t": "B738",
      "alt_baro": 2350,
      "alt_geom": 2475,
      "gs": 198.4,
      "track": 271.3,
      "baro_rate": -1088,
      "geom_rate": -1024,
      "lat": 51.501200,
      "lon": -0.099800,
      "seen_pos": 1.4,
      "messages": 41233,
      "seen": 0.3,
      "rssi": -12.7
    },
    {
      "hex": "40631a",
      "flight": "EZY44QP",
      "alt_baro": "ground",
      "gs": 12.1,
      "lat": 51.470100,
      "lon": -0.454200,
      "seen_pos": 0.6
    },
    {
      "hex": "a1b2c3",
      "flight": "NOPOS1",
      "alt_baro": 34000,
      "seen_pos": 2.0
    }
  ],
  "msg": "No error",
  "now": 1755638070.5,
  "total": 3
}
''';

/// OpenSky returns positional arrays, not objects, which is exactly the sort
/// of format that breaks silently when a field moves. Index 13 is geometric
/// altitude, 7 is barometric; both are metres.
const String _openSkyBody = '''
{
  "time": 1755638070,
  "states": [
    ["4ca2d1", "RYR8452 ", "Ireland", 1755638068, 1755638069,
     -0.0998, 51.5012, 716.28, false, 102.1, 271.3, -5.2, null, 754.38,
     "7241", false, 0],
    ["40631a", "EZY44QP ", "United Kingdom", 1755638060, 1755638069,
     -0.4542, 51.4701, null, true, 6.2, 88.0, null, null, null,
     "2000", false, 0],
    ["deadbe", null, "Unknown", null, 1755638000,
     null, null, null, false, null, null, null, null, null,
     null, false, 0]
  ]
}
''';

void main() {
  group('tar1090 (adsb.lol / airplanes.live)', () {
    late List<AircraftSample> samples;

    setUp(() {
      samples = Tar1090Source.parse(_tar1090Body, 'adsb.lol');
    });

    test('an aircraft without a position is dropped, not defaulted to 0,0', () {
      // A sample at lat 0 lon 0 would sit in the Gulf of Guinea and score as
      // 5,000 km away (harmless) but a null-coalesced 0 would silently
      // corrupt any later averaging. Drop it instead.
      expect(samples.map((AircraftSample s) => s.icao24),
          isNot(contains('a1b2c3')));
      expect(samples, hasLength(2));
    });

    test('the identifying fields are read and normalised', () {
      final AircraftSample s = samples.first;

      expect(s.icao24, '4ca2d1'); // upper case in the feed, lower case here
      expect(s.callsign, 'RYR8452'); // feed pads callsigns to 8 characters
      expect(s.registration, 'EI-DYH');
      expect(s.aircraftType, 'B738');
      expect(s.latitude, closeTo(51.5012, 1e-9));
      expect(s.longitude, closeTo(-0.0998, 1e-9));
      expect(s.groundSpeedKt, closeTo(198.4, 1e-9));
      expect(s.trackDeg, closeTo(271.3, 1e-9));
      expect(s.source, 'adsb.lol');
      expect(s.onGround, isFalse);
    });

    test('geometric altitude wins over barometric', () {
      // Barometric altitude is referenced to the standard pressure setting, so
      // on a low-pressure day it can read a few hundred feet out. For a 900 ft
      // overflight that is the difference between "overhead" and "not".
      expect(samples.first.altitudeFt, 2475); // alt_geom, not alt_baro 2350
      expect(samples.first.verticalRateFpm, -1024); // geom_rate, not baro_rate
    });

    test('"ground" as an altitude means on the ground, not a parse failure',
        () {
      final AircraftSample taxiing =
          samples.firstWhere((AircraftSample s) => s.icao24 == '40631a');

      expect(taxiing.onGround, isTrue);
      expect(taxiing.altitudeFt, isNull);
    });

    test('seen_pos is subtracted, so the position carries its own age', () {
      // `now` is 1755638070.5 and this position was seen 1.4 s ago. Treating
      // every sample as current would smear a 200 kt aircraft over 140 m.
      final DateTime expected = DateTime.fromMillisecondsSinceEpoch(
        1755638070500 - 1400,
        isUtc: true,
      );
      expect(samples.first.timestamp.toUtc(), expected);
    });

    test('`now` in milliseconds is handled as well as `now` in seconds', () {
      // tar1090 emits seconds; some hosted variants emit milliseconds. Guessing
      // wrong puts every timestamp in 1970 or in the year 57000.
      final List<AircraftSample> ms = Tar1090Source.parse(
        _tar1090Body.replaceAll('"now": 1755638070.5', '"now": 1755638070500'),
        'adsb.lol',
      );
      expect(ms.first.timestamp.toUtc().year, 2025);
      expect(
        ms.first.timestamp.difference(samples.first.timestamp).inMilliseconds,
        0,
      );
    });

    test('an empty or errored feed yields no candidates rather than throwing',
        () {
      expect(Tar1090Source.parse('{"ac": [], "now": 1}', 'adsb.lol'), isEmpty);
      expect(Tar1090Source.parse('{"now": 1}', 'adsb.lol'), isEmpty);
      expect(
        () => Tar1090Source.parse('[]', 'adsb.lol'),
        throwsA(isA<AdsbException>()),
      );
    });
  });

  group('OpenSky state vectors', () {
    late List<AircraftSample> samples;

    setUp(() {
      samples = OpenSkySource.parseStates(_openSkyBody);
    });

    test('rows without a position are skipped', () {
      expect(samples, hasLength(2));
      expect(
        samples.map((AircraftSample s) => s.icao24),
        isNot(contains('deadbe')),
      );
    });

    test('metric units are converted, geometric altitude preferred', () {
      final AircraftSample s = samples.first;

      expect(s.icao24, '4ca2d1');
      expect(s.callsign, 'RYR8452');
      // Index 13 (geo_altitude) 754.38 m, not index 7 (baro) 716.28 m.
      expect(s.altitudeFt, closeTo(754.38 * kFeetPerMetre, 0.01));
      expect(
          s.altitudeFt, closeTo(2475, 1)); // same aircraft as the tar1090 row
      expect(s.groundSpeedKt,
          closeTo(102.1 * 3600 / kMetresPerNauticalMile, 0.01));
      expect(s.groundSpeedKt, closeTo(198.4, 0.5));
      expect(s.verticalRateFpm, closeTo(-5.2 * 60 * kFeetPerMetre, 0.01));
      expect(s.trackDeg, closeTo(271.3, 1e-9));
      expect(s.source, 'OpenSky');
    });

    test('time_position is used in preference to last_contact', () {
      // last_contact only means the transponder was heard; time_position is
      // when the coordinates were valid. They differ by a second here, which
      // is 100 m of aircraft.
      expect(
        samples.first.timestamp.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1755638068 * 1000, isUtc: true),
      );
    });

    test('on_ground and a missing altitude survive together', () {
      final AircraftSample taxiing = samples.last;
      expect(taxiing.onGround, isTrue);
      expect(taxiing.altitudeFt, isNull);
    });

    test('a null or malformed body yields no candidates rather than throwing',
        () {
      expect(OpenSkySource.parseStates('{"states": null}'), isEmpty);
      expect(OpenSkySource.parseStates('{}'), isEmpty);
      expect(OpenSkySource.parseStates('[]'), isEmpty);
    });
  });
}
