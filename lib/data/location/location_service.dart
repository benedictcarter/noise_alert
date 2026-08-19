import 'package:geolocator/geolocator.dart';

/// Where the snap was taken.
class SnapLocation {
  const SnapLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.altitudeM,
    this.fixedAt,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;

  /// Metres above mean sea level; used as the ground reference when working out
  /// how high the aircraft was above the listener.
  final double? altitudeM;

  final DateTime? fixedAt;

  /// A fix this poor makes the geometry meaningless, so the UI warns rather
  /// than quietly matching against the wrong bit of sky.
  bool get isUsable => (accuracyM ?? 0) <= 100;
}

class LocationUnavailable implements Exception {
  LocationUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class LocationService {
  const LocationService();

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationUnavailable(
          'Location services are turned off on this device.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationUnavailable(
        'Location permission is permanently denied. Enable it in system settings.',
      );
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<SnapLocation> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!await ensurePermission()) {
      throw LocationUnavailable('Location permission was not granted.');
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: timeout,
      ),
    );

    return SnapLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      altitudeM: position.altitude,
      fixedAt: position.timestamp,
    );
  }

  /// Last known fix, used to start the aircraft poll immediately rather than
  /// waiting several seconds for a fresh one.
  Future<SnapLocation?> lastKnown() async {
    final Position? position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return SnapLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyM: position.accuracy,
      altitudeM: position.altitude,
      fixedAt: position.timestamp,
    );
  }
}
