import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';
import 'package:noise_alert/snap/snap.dart';
import 'package:noise_alert/map/geometry.dart';
import 'package:noise_alert/map/layers.dart';
import 'package:noise_alert/map/projection.dart';

/// Somewhere under a real flight path, so the longitude scaling is exercised at
/// a latitude the app is actually used at rather than at the equator, where
/// cos(lat) is 1 and every mistake cancels.
const double _lat = 51.4700;
const double _lon = -0.4543;

final DateTime _t0 = DateTime.utc(2026, 3, 4, 19, 30);

TrackPoint _point(int seconds, double lat, double lon) => TrackPoint(
      time: _t0.add(Duration(seconds: seconds)),
      latitude: lat,
      longitude: lon,
      altitudeFt: 2400,
    );

AircraftSample _sample({
  String icao24 = 'a1b2c3',
  double lat = _lat,
  double lon = _lon,
}) =>
    AircraftSample(
      icao24: icao24,
      timestamp: _t0,
      latitude: lat,
      longitude: lon,
      callsign: 'BAW123',
      altitudeFt: 2400,
      source: 'test',
    );

/// Metres north/east of the reference point, as a coordinate.
///
/// Good enough over a few kilometres, which is the only distance this file
/// cares about.
(double, double) _offsetMetres(double northM, double eastM) {
  const double mPerDegLat = kEarthRadiusM * math.pi / 180.0;
  final double mPerDegLon = mPerDegLat * math.cos(degToRad(_lat));
  return (_lat + northM / mPerDegLat, _lon + eastM / mPerDegLon);
}

void main() {
  group('MapFrame', () {
    test('falls back to the 1 km square when there is nothing to fit', () {
      final MapFrame frame = MapFrame.around(_lat, _lon);
      expect(frame.spanM, MapFrame.defaultSpanM);
      expect(frame.latitude, _lat);
      expect(frame.longitude, _lon);
    });

    test('stays centred on the observer however far the aircraft is', () {
      final (double lat, double lon) = _offsetMetres(2000, 2000);
      final MapFrame frame = MapFrame.around(
        _lat,
        _lon,
        points: <TrackPoint>[_point(0, lat, lon)],
      );
      // The house, not the midpoint. A frame that splits the difference
      // eventually leaves the house off the edge.
      expect(frame.latitude, _lat);
      expect(frame.longitude, _lon);
    });

    test('grows to hold a track, with a margin', () {
      final (double lat, double lon) = _offsetMetres(800, 0);
      final MapFrame frame = MapFrame.around(
        _lat,
        _lon,
        points: <TrackPoint>[_point(0, _lat, _lon), _point(3, lat, lon)],
      );
      // 800 m out needs 1600 m of span, plus the 15% margin.
      expect(frame.spanM, closeTo(1600 * 1.15, 20));
      expect(haversineMetres(_lat, _lon, frame.north, _lon), greaterThan(800));
    });

    test('ignores the far end of a flight rather than zooming out to it', () {
      final (double near, double nearLon) = _offsetMetres(600, 0);
      final (double far, double farLon) = _offsetMetres(40000, 0);
      final MapFrame frame = MapFrame.around(
        _lat,
        _lon,
        points: <TrackPoint>[
          _point(0, near, nearLon),
          _point(60, far, farLon),
        ],
      );
      expect(frame.spanM, closeTo(1200 * 1.15, 20));
      expect(frame.spanM, lessThan(MapFrame.maxSpanM));
    });

    test('sizes to the nearest point when the whole track is far away', () {
      final (double lat, double lon) = _offsetMetres(5000, 0);
      final MapFrame frame = MapFrame.around(
        _lat,
        _lon,
        points: <TrackPoint>[_point(0, lat, lon)],
      );
      // Clamped to the maximum rather than left at the 1 km default: the
      // reader should at least be able to see which way it went past.
      expect(frame.spanM, MapFrame.maxSpanM);
    });

    test('does not blow up near the pole', () {
      final MapFrame frame = MapFrame.around(89.9, 0);
      expect(frame.north, lessThanOrEqualTo(85.0));
      expect((frame.east - frame.west).isFinite, isTrue);
    });
  });

  group('MercatorView', () {
    test('projects the centre to the middle of the image', () {
      const MercatorView view = MercatorView(
        centreLat: _lat,
        centreLon: _lon,
        zoom: 14,
        width: 900,
        height: 640,
      );
      final Offset at = view.project(_lat, _lon);
      expect(at.dx, closeTo(450, 0.001));
      expect(at.dy, closeTo(320, 0.001));
    });

    test('puts north up and east right', () {
      const MercatorView view = MercatorView(
        centreLat: _lat,
        centreLon: _lon,
        zoom: 14,
        width: 900,
        height: 640,
      );
      expect(view.project(_lat + 0.01, _lon).dy, lessThan(320));
      expect(view.project(_lat, _lon + 0.01).dx, greaterThan(450));
    });

    test('metresPerPixel agrees with what it actually projects', () {
      const MercatorView view = MercatorView(
        centreLat: _lat,
        centreLon: _lon,
        zoom: 15,
        width: 900,
        height: 640,
      );
      final (double lat, double lon) = _offsetMetres(0, 500);
      final double px =
          (view.project(lat, lon).dx - view.project(_lat, _lon).dx).abs();
      expect(px * view.metresPerPixel, closeTo(500, 5));
    });

    test('fit holds the whole frame inside the image', () {
      const MapFrame frame = MapFrame(
        latitude: _lat,
        longitude: _lon,
        spanM: 1200,
      );
      final MercatorView view =
          MercatorView.fit(frame, width: 900, height: 640);

      for (final Offset corner in <Offset>[
        view.project(frame.north, frame.west),
        view.project(frame.north, frame.east),
        view.project(frame.south, frame.west),
        view.project(frame.south, frame.east),
      ]) {
        expect(corner.dx, inInclusiveRange(0, 900));
        expect(corner.dy, inInclusiveRange(0, 640));
      }
    });

    test('forImage keeps the geometry on the same streets at 3x', () {
      const MapFrame frame = MapFrame(
        latitude: _lat,
        longitude: _lon,
        spanM: 1200,
      );
      final MercatorView logical =
          MercatorView.fit(frame, width: 900, height: 640);
      // iOS hands back an image at the screen scale, not the size asked for.
      final MercatorView actual = logical.forImage(
        imageWidth: 2700,
        imageHeight: 1920,
        requestedWidth: 900,
      );

      final (double lat, double lon) = _offsetMetres(300, 300);
      final Offset small = logical.project(lat, lon);
      final Offset big = actual.project(lat, lon);
      expect(big.dx, closeTo(small.dx * 3, 0.001));
      expect(big.dy, closeTo(small.dy * 3, 0.001));
    });
  });

  group('MapAircraft', () {
    test('heading comes from the last movement actually made', () {
      final (double north, double northLon) = _offsetMetres(1000, 0);
      final MapAircraft a = MapAircraft(
        id: 'a1b2c3',
        label: 'BAW123',
        points: <TrackPoint>[_point(0, _lat, _lon), _point(3, north, northLon)],
      );
      expect(a.headingDeg, closeTo(0, 1));
    });

    test('skips repeated positions rather than reporting no heading', () {
      final (double east, double eastLon) = _offsetMetres(0, 1000);
      final MapAircraft a = MapAircraft(
        id: 'a1b2c3',
        label: 'BAW123',
        points: <TrackPoint>[
          _point(0, _lat, _lon),
          _point(3, east, eastLon),
          // A stale report repeated by the feed: two identical positions in a
          // row would otherwise look like an aircraft with no direction.
          _point(6, east, eastLon),
        ],
      );
      expect(a.headingDeg, closeTo(90, 1));
    });

    test('a single position has no heading', () {
      final MapAircraft a = MapAircraft(
        id: 'a1b2c3',
        label: 'BAW123',
        points: <TrackPoint>[_point(0, _lat, _lon)],
      );
      expect(a.headingDeg, isNull);
      expect(a.head, isNotNull);
    });

    test('a candidate with no stored track still has a position to draw', () {
      final MapAircraft a = MapAircraft.ofCandidate(
        FlightCandidate(
          aircraft: _sample(),
          closestApproachTime: _t0,
          slantRangeM: 900,
          horizontalRangeM: 300,
          heightAboveObserverM: 850,
          elevationDegrees: 70,
          score: 1,
          extrapolated: false,
        ),
      );
      expect(a.points, hasLength(1));
      expect(a.head!.latitude, _lat);
      expect(a.label, 'BAW123');
    });
  });

  group('GeoJSON', () {
    test('coordinates are longitude first', () {
      final Map<String, Object?> json = observerGeoJson(_lat, _lon);
      final List<Object?> features = json['features']! as List<Object?>;
      final Map<String, Object?> geometry = (features.single
          as Map<String, Object?>)['geometry']! as Map<String, Object?>;
      // Getting this backwards puts London in the Indian Ocean and the map
      // just shows sea, with no error anywhere.
      expect(geometry['coordinates'], <double>[_lon, _lat]);
    });

    test('no fix means no observer feature, not a feature at zero', () {
      expect(
          (observerGeoJson(null, null)['features']! as List<Object?>), isEmpty);
      expect(
          (observerGeoJson(_lat, null)['features']! as List<Object?>), isEmpty);
    });

    test('a one-point aircraft gets a marker but no line', () {
      final List<MapAircraft> aircraft = <MapAircraft>[
        MapAircraft(
          id: 'a1b2c3',
          label: 'BAW123',
          points: <TrackPoint>[_point(0, _lat, _lon)],
        ),
      ];
      expect((trackGeoJson(aircraft)['features']! as List<Object?>), isEmpty);
      expect(
          (planeGeoJson(aircraft)['features']! as List<Object?>), hasLength(1));
    });

    test('heading is zero rather than null when nothing has moved', () {
      final List<Object?> features = planeGeoJson(<MapAircraft>[
        MapAircraft(
          id: 'a1b2c3',
          label: 'BAW123',
          points: <TrackPoint>[_point(0, _lat, _lon)],
        ),
      ])['features']! as List<Object?>;
      final Map<String, Object?> props = (features.single
          as Map<String, Object?>)['properties']! as Map<String, Object?>;
      // A data-driven icon-rotate reading null renders nothing at all on
      // Android, so the aeroplane would silently vanish.
      expect(props['heading'], 0.0);
      expect(props['highlighted'], false);
    });
  });

  group('decimateTrack', () {
    test('leaves a short track alone', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 10; i++) _point(i * 3, _lat + i * 0.001, _lon),
      ];
      expect(decimateTrack(points, 60), same(points));
    });

    test('keeps both ends and hits the cap exactly', () {
      final List<TrackPoint> points = <TrackPoint>[
        for (int i = 0; i < 200; i++) _point(i * 3, _lat + i * 0.001, _lon),
      ];
      final List<TrackPoint> thinned = decimateTrack(points, 60);
      expect(thinned, hasLength(60));
      expect(thinned.first.time, points.first.time);
      expect(thinned.last.time, points.last.time);
      // Still in order: a thinned track drawn out of sequence is a scribble.
      for (int i = 1; i < thinned.length; i++) {
        expect(thinned[i].time.isAfter(thinned[i - 1].time), isTrue);
      }
    });
  });

  group('stored tracks', () {
    test('a TrackPoint survives the round trip', () {
      final TrackPoint before = _point(12, _lat, _lon);
      final TrackPoint after = TrackPoint.fromJson(
        jsonDecode(jsonEncode(before.toJson())) as List<Object?>,
      );
      expect(after.time, before.time);
      expect(after.latitude, before.latitude);
      expect(after.longitude, before.longitude);
      expect(after.altitudeFt, before.altitudeFt);
    });

    test('the track rides along inside match_json', () {
      final FlightMatch match = FlightMatch(
        candidates: <FlightCandidate>[
          FlightCandidate(
            aircraft: _sample(),
            closestApproachTime: _t0,
            slantRangeM: 900,
            horizontalRangeM: 300,
            heightAboveObserverM: 850,
            elevationDegrees: 70,
            score: 1,
            extrapolated: false,
            track: <TrackPoint>[
              _point(0, _lat, _lon),
              _point(3, _lat + 0.01, _lon),
            ],
          ),
        ],
        confidence: 0.9,
        searchedFrom: _t0.subtract(const Duration(seconds: 45)),
        searchedTo: _t0.add(const Duration(seconds: 10)),
      );

      final FlightMatch after = decodeMatch(
        jsonDecode(jsonEncode(encodeMatch(match))) as Map<String, Object?>,
      );
      expect(after.candidates.single.track, hasLength(2));
      expect(after.candidates.single.track.last.latitude,
          closeTo(_lat + 0.01, 1e-9));
    });

    test('a row stored before the map existed decodes with an empty track', () {
      // Verbatim shape of a pre-v2 match_json: no 'track' key anywhere.
      const String legacy = '''
{"confidence":0.8,
 "searchedFrom":"2026-03-04T19:29:15.000Z",
 "searchedTo":"2026-03-04T19:30:10.000Z",
 "selectedIcao24":null,
 "note":null,
 "candidates":[{"aircraft":{"icao24":"a1b2c3",
   "timestamp":"2026-03-04T19:30:00.000Z",
   "latitude":51.47,"longitude":-0.4543,"callsign":"BAW123",
   "registration":null,"aircraftType":null,"altitudeFt":2400,
   "groundSpeedKt":null,"trackDeg":null,"verticalRateFpm":null,
   "onGround":false,"source":"test"},
  "closestApproachTime":"2026-03-04T19:30:00.000Z",
  "slantRangeM":900.0,"horizontalRangeM":300.0,
  "heightAboveObserverM":850.0,"elevationDegrees":70.0,
  "score":1.0,"extrapolated":false}]}''';

      final FlightMatch match =
          decodeMatch(jsonDecode(legacy) as Map<String, Object?>);
      expect(match.candidates.single.track, isEmpty);
      // And it is still drawable: one dot, no line.
      final MapAircraft a = MapAircraft.ofCandidate(match.candidates.single);
      expect(a.points, hasLength(1));
    });
  });
}
