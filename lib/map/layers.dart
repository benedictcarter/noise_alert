import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';

/// Source and layer ids, in one place so the widget and its tests agree.
class MapIds {
  static const String observerSource = 'na-observer-src';
  static const String observerHalo = 'na-observer-halo';
  static const String observerDot = 'na-observer-dot';

  static const String trackSource = 'na-track-src';
  static const String trackLine = 'na-track-line';

  static const String planeSource = 'na-plane-src';
  static const String planeIcon = 'na-plane-icon';
  static const String planeLabel = 'na-plane-label';

  /// Registered with [MapLibreMapController.addImage] before the symbol layer
  /// that names them exists, because a symbol layer whose icon is missing
  /// silently draws nothing.
  static const String planeImage = 'na-plane';
  static const String planeImageDim = 'na-plane-dim';
}

/// One aeroplane as the map draws it.
///
/// Deliberately not [AircraftTrack] or [FlightCandidate]: the live map has the
/// former, the review screen and the emailed picture have the latter, and the
/// map should not know or care which it was handed.
class MapAircraft {
  const MapAircraft({
    required this.id,
    required this.label,
    required this.points,
    this.highlighted = false,
  });

  MapAircraft.ofTrack(AircraftTrack track, {this.highlighted = false})
      : id = track.icao24,
        label = track.latest.displayName,
        points = track.points;

  MapAircraft.ofCandidate(FlightCandidate candidate, {this.highlighted = false})
      : id = candidate.aircraft.icao24,
        label = candidate.aircraft.displayName,
        points = candidate.track.isEmpty
            ? <TrackPoint>[TrackPoint.of(candidate.aircraft)]
            : candidate.track;

  final String id;
  final String label;

  /// Oldest first.
  final List<TrackPoint> points;

  /// The one the complaint is about. Everything else is drawn faintly, as
  /// context: it matters that the sky was busy, but not as much as which
  /// aeroplane this is.
  final bool highlighted;

  /// Where it is now, or where it was last seen.
  TrackPoint? get head => points.isEmpty ? null : points.last;

  /// Which way it is pointing, from the last movement it actually made.
  ///
  /// Not the ADS-B track angle, which the map does not carry, but the direction
  /// between the last two distinct positions is observed rather than reported,
  /// and it is the one that matches the line drawn behind it.
  double? get headingDeg {
    for (int i = points.length - 2; i >= 0; i--) {
      final TrackPoint a = points[i];
      final TrackPoint b = points.last;
      if (a.latitude == b.latitude && a.longitude == b.longitude) continue;
      return bearingDegrees(a.latitude, a.longitude, b.latitude, b.longitude);
    }
    return null;
  }
}

Map<String, Object?> _feature(
  Map<String, Object?> geometry,
  Map<String, Object?> properties,
) =>
    <String, Object?>{
      'type': 'Feature',
      'geometry': geometry,
      'properties': properties,
    };

Map<String, Object?> _collection(List<Map<String, Object?>> features) =>
    <String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    };

/// GeoJSON positions are `[longitude, latitude]`, in that order. Getting this
/// backwards puts London in the Indian Ocean and the map simply shows sea.
List<double> _lngLat(double latitude, double longitude) =>
    <double>[longitude, latitude];

/// The house.
Map<String, Object?> observerGeoJson(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return _collection(const []);
  return _collection(<Map<String, Object?>>[
    _feature(
      <String, Object?>{
        'type': 'Point',
        'coordinates': _lngLat(latitude, longitude),
      },
      const <String, Object?>{},
    ),
  ]);
}

/// One LineString per aircraft, for the path flown.
///
/// An aircraft seen only once has no line: a single position is a dot, and
/// joining it to nothing would be inventing a direction of travel.
Map<String, Object?> trackGeoJson(List<MapAircraft> aircraft) => _collection(
      <Map<String, Object?>>[
        for (final MapAircraft a in aircraft)
          if (a.points.length >= 2)
            _feature(
              <String, Object?>{
                'type': 'LineString',
                'coordinates': <List<double>>[
                  for (final TrackPoint p in a.points)
                    _lngLat(p.latitude, p.longitude),
                ],
              },
              <String, Object?>{
                'id': a.id,
                'highlighted': a.highlighted,
              },
            ),
      ],
    );

/// One Point per aircraft, at its latest position.
Map<String, Object?> planeGeoJson(List<MapAircraft> aircraft) => _collection(
      <Map<String, Object?>>[
        for (final MapAircraft a in aircraft)
          if (a.head != null)
            _feature(
              <String, Object?>{
                'type': 'Point',
                'coordinates': _lngLat(a.head!.latitude, a.head!.longitude),
              },
              <String, Object?>{
                'id': a.id,
                'label': a.label,
                'highlighted': a.highlighted,
                // Zero, not null, when the aircraft has not moved: a
                // data-driven `icon-rotate` reading a null property renders
                // nothing at all on Android rather than falling back.
                'heading': a.headingDeg ?? 0.0,
              },
            ),
      ],
    );

/// Every point the frame should try to hold: the aircraft paths, near enough
/// to the house to be worth showing.
List<TrackPoint> framePoints(List<MapAircraft> aircraft) => <TrackPoint>[
      for (final MapAircraft a in aircraft) ...a.points,
    ];
