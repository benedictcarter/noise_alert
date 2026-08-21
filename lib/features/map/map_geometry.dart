import 'dart:math' as math;

import '../../core/geo.dart';
import '../../domain/aircraft.dart';

/// Metres per degree of latitude. Constant enough at any scale a street map is
/// drawn at; the equivalent for longitude is not, which is why it is computed.
const double _metresPerDegreeLat = kEarthRadiusM * math.pi / 180.0;

/// The square of ground a map should show.
///
/// Always centred on the observer, never on the aircraft or on the middle of
/// the two. The complaint is about a house, and a frame that drifts to keep an
/// aeroplane centred is a frame that eventually leaves the house off the edge —
/// which is the one thing the picture exists to show.
class MapFrame {
  const MapFrame({
    required this.latitude,
    required this.longitude,
    required this.spanM,
  });

  final double latitude;
  final double longitude;

  /// Side of the square, in metres.
  final double spanM;

  double get _halfLatDeg => (spanM / 2) / _metresPerDegreeLat;

  double get _halfLonDeg {
    // cos(lat) collapses at the poles and would blow the frame up to the whole
    // globe. Nobody complains about aircraft noise at 89°N, but a divide by
    // almost-zero is not the way to find that out.
    final double scale = math.max(math.cos(degToRad(latitude)), 0.01);
    return (spanM / 2) / (_metresPerDegreeLat * scale);
  }

  double get south => (latitude - _halfLatDeg).clamp(-85.0, 85.0);
  double get north => (latitude + _halfLatDeg).clamp(-85.0, 85.0);
  double get west => longitude - _halfLonDeg;
  double get east => longitude + _halfLonDeg;

  /// The 1 km square of the TODO, when there is nothing else to go on.
  static const double defaultSpanM = 1000;

  /// Beyond this the house is a few pixels and the picture stops being about a
  /// house. A candidate further out than [focusRadiusM] is shown by pointing at
  /// it, not by zooming out until both fit.
  static const double maxSpanM = 8000;

  /// Track points further from the observer than this are ignored when sizing
  /// the frame. An aircraft's reported path runs for tens of kilometres either
  /// side of the flyover, and fitting all of it would reduce the street to a
  /// dot every time.
  static const double focusRadiusM = 3000;

  /// A frame around [latitude], [longitude] that holds as much of [points] as
  /// is worth holding.
  static MapFrame around(
    double latitude,
    double longitude, {
    List<TrackPoint> points = const <TrackPoint>[],
    double minSpanM = defaultSpanM,
    double maxSpan = maxSpanM,
    double focusRadius = focusRadiusM,
  }) {
    double wanted = 0;
    double nearest = double.infinity;
    for (final TrackPoint p in points) {
      final double d = haversineMetres(
          latitude, longitude, p.latitude, p.longitude);
      if (d < nearest) nearest = d;
      if (d <= focusRadius && d > wanted) wanted = d;
    }

    // Everything was outside the focus radius: size to the closest point the
    // aircraft managed rather than to the arbitrary default, so the reader can
    // at least see which way it went past.
    if (wanted == 0 && nearest.isFinite) wanted = nearest;

    // 15% margin, so a track that just reaches the corner is not drawn along
    // the frame edge.
    final double span = wanted * 2 * 1.15;
    return MapFrame(
      latitude: latitude,
      longitude: longitude,
      spanM: span.clamp(minSpanM, maxSpan),
    );
  }
}
