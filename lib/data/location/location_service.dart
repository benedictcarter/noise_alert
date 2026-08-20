import 'package:geolocator/geolocator.dart';

/// Where the snap was taken.
class SnapLocation {
  const SnapLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.altitudeM,
    this.fixedAt,
    this.stale = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracyM;

  /// Metres above mean sea level; used as the ground reference when working out
  /// how high the aircraft was above the listener.
  final double? altitudeM;

  final DateTime? fixedAt;

  /// True when this came from the last-known cache rather than a fresh fix, so
  /// the UI and the letter can say so instead of implying the user was
  /// definitely standing here.
  final bool stale;

  /// A fix this poor makes the geometry meaningless, so the UI warns rather
  /// than quietly matching against the wrong bit of sky.
  bool get isUsable => (accuracyM ?? 0) <= 100;
}

/// Why the location layer cannot currently produce a fix.
///
/// A single "it failed" is not enough: "turn location on", "grant the
/// permission", and "go to system settings because I can no longer ask" are
/// three different actions for the user, and only one of them is a tap away.
enum LocationAvailability {
  /// Permission granted and the device's location services are on.
  ready,

  /// Location services are switched off device-wide.
  serviceDisabled,

  /// Not granted yet, but the system will still show a prompt if asked.
  denied,

  /// Denied permanently (or blocked by policy). Only system settings can undo
  /// this — asking again silently returns denied without showing anything.
  deniedForever,
}

class LocationStatus {
  const LocationStatus(this.availability, {this.lastFix});

  final LocationAvailability availability;

  /// Best fix known at the time of the check, if any.
  final SnapLocation? lastFix;

  bool get isReady => availability == LocationAvailability.ready;

  String get message {
    switch (availability) {
      case LocationAvailability.ready:
        return 'Location ready.';
      case LocationAvailability.serviceDisabled:
        return 'Location is switched off on this device. '
            'Turn it on to identify the aircraft.';
      case LocationAvailability.denied:
        return 'Location permission has not been granted yet.';
      case LocationAvailability.deniedForever:
        return 'Location permission is blocked. Enable it in system settings '
            'to identify the aircraft.';
    }
  }
}

class LocationUnavailable implements Exception {
  LocationUnavailable(this.reason, [this.availability]);
  final String reason;
  final LocationAvailability? availability;
  @override
  String toString() => reason;
}

class LocationService {
  const LocationService();

  /// Reports what is currently possible **without** prompting the user.
  ///
  /// The snap screen calls this on every resume so it can show the true state
  /// rather than discovering it only when a capture is already under way.
  Future<LocationStatus> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationStatus(LocationAvailability.serviceDisabled);
    }
    final LocationPermission permission = await Geolocator.checkPermission();
    return LocationStatus(_map(permission), lastFix: await lastKnown());
  }

  /// Asks for the permission if the system will still show a prompt.
  ///
  /// Called when the snap screen opens rather than mid-capture: a permission
  /// dialog appearing *after* the button press steals the seconds during which
  /// the aircraft is still overhead, and the user is reading a dialog instead
  /// of listening.
  Future<LocationStatus> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationStatus(LocationAvailability.serviceDisabled);
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return LocationStatus(_map(permission), lastFix: await lastKnown());
  }

  Future<bool> ensurePermission() async => (await request()).isReady;

  /// Opens the OS screen that can fix whatever [status] reports.
  Future<void> openRelevantSettings(LocationAvailability availability) async {
    if (availability == LocationAvailability.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// A fix, or an exception explaining precisely what is missing.
  ///
  /// Falls back from a high-accuracy fix to a coarse one rather than failing
  /// outright: indoors, or under cloud on a cold receiver, `best` can miss its
  /// deadline while the network provider has had a perfectly serviceable
  /// several-hundred-metre fix all along. For picking an aircraft out of a
  /// 25 nm query, several hundred metres is fine — the slant ranges involved
  /// are kilometres.
  Future<SnapLocation> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final LocationStatus status = await request();
    if (!status.isReady) {
      throw LocationUnavailable(status.message, status.availability);
    }

    // Two thirds of the budget on a precise fix, the rest on a coarse one.
    final Duration precise = timeout * (2 / 3);
    try {
      return _from(
        await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: precise,
          ),
        ),
      );
    } on Object {
      // Falls through to the coarse attempt.
    }

    try {
      return _from(
        await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: timeout - precise,
          ),
        ),
      );
    } on Object {
      throw LocationUnavailable(
        'No location fix within ${timeout.inSeconds} s. '
        'Under a roof the receiver can take a minute from cold.',
        LocationAvailability.ready,
      );
    }
  }

  /// Last known fix, used to start the aircraft poll immediately rather than
  /// waiting several seconds for a fresh one.
  Future<SnapLocation?> lastKnown() async {
    try {
      final Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) return null;
      return _from(position, stale: true);
    } on Object {
      // Throws rather than returning null when the permission is missing.
      return null;
    }
  }

  static SnapLocation _from(Position position, {bool stale = false}) =>
      SnapLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        altitudeM: position.altitude,
        fixedAt: position.timestamp,
        stale: stale,
      );

  static LocationAvailability _map(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAvailability.ready;
      case LocationPermission.deniedForever:
        return LocationAvailability.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAvailability.denied;
    }
  }
}
