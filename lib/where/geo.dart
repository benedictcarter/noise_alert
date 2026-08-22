import 'dart:math' as math;

const double kEarthRadiusM = 6371008.8;
const double kFeetPerMetre = 3.28084;
const double kMetresPerNauticalMile = 1852.0;

double degToRad(double d) => d * math.pi / 180.0;
double radToDeg(double r) => r * 180.0 / math.pi;

/// Great-circle distance in metres.
double haversineMetres(double lat1, double lon1, double lat2, double lon2) {
  final double dLat = degToRad(lat2 - lat1);
  final double dLon = degToRad(lon2 - lon1);
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(degToRad(lat1)) *
          math.cos(degToRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * kEarthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Initial bearing from point 1 to point 2, degrees clockwise from true north.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final double phi1 = degToRad(lat1);
  final double phi2 = degToRad(lat2);
  final double dLambda = degToRad(lon2 - lon1);
  final double y = math.sin(dLambda) * math.cos(phi2);
  final double x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (radToDeg(math.atan2(y, x)) + 360) % 360;
}

/// Moves a point [distanceM] along [bearingDeg]. Used for dead reckoning.
({double latitude, double longitude}) destinationPoint(
  double lat,
  double lon,
  double bearingDeg,
  double distanceM,
) {
  final double delta = distanceM / kEarthRadiusM;
  final double theta = degToRad(bearingDeg);
  final double phi1 = degToRad(lat);
  final double lambda1 = degToRad(lon);

  final double sinPhi2 = math.sin(phi1) * math.cos(delta) +
      math.cos(phi1) * math.sin(delta) * math.cos(theta);
  final double phi2 = math.asin(sinPhi2);
  final double lambda2 = lambda1 +
      math.atan2(
        math.sin(theta) * math.sin(delta) * math.cos(phi1),
        math.cos(delta) - math.sin(phi1) * sinPhi2,
      );

  return (
    latitude: radToDeg(phi2),
    longitude: (radToDeg(lambda2) + 540) % 360 - 180,
  );
}

/// Straight-line distance through the air, given a horizontal separation and a
/// height difference.
double slantRangeMetres(double horizontalM, double heightM) =>
    math.sqrt(horizontalM * horizontalM + heightM * heightM);

/// Angle above the horizon, degrees. 90 is directly overhead.
double elevationDegrees(double horizontalM, double heightM) {
  if (horizontalM <= 0) return heightM > 0 ? 90 : 0;
  return radToDeg(math.atan2(heightM, horizontalM));
}

/// How long sound takes to cover [distanceM].
Duration soundTravelTime(double distanceM, {double speedOfSoundMs = 343.0}) =>
    Duration(microseconds: (distanceM / speedOfSoundMs * 1e6).round());
