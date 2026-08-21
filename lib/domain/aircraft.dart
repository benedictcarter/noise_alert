/// One ADS-B position report for one aircraft at one instant.
class AircraftSample {
  const AircraftSample({
    required this.icao24,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.callsign,
    this.registration,
    this.aircraftType,
    this.altitudeFt,
    this.groundSpeedKt,
    this.trackDeg,
    this.verticalRateFpm,
    this.onGround = false,
    this.source = '',
  });

  /// 24-bit ICAO address, lower case hex. The only globally stable identifier
  /// here — callsigns are reused daily and registrations can be absent.
  final String icao24;
  final DateTime timestamp;
  final double latitude;
  final double longitude;

  /// Usually the flight number for airline traffic (e.g. `BAW123`).
  final String? callsign;
  final String? registration;
  final String? aircraftType;

  /// Barometric altitude, feet above mean sea level.
  final double? altitudeFt;
  final double? groundSpeedKt;
  final double? trackDeg;
  final double? verticalRateFpm;
  final bool onGround;
  final String source;

  String get displayName {
    final String? cs = callsign?.trim();
    if (cs != null && cs.isNotEmpty) return cs;
    final String? reg = registration?.trim();
    if (reg != null && reg.isNotEmpty) return reg;
    return icao24.toUpperCase();
  }

  AircraftSample copyWith({
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? altitudeFt,
  }) =>
      AircraftSample(
        icao24: icao24,
        timestamp: timestamp ?? this.timestamp,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        callsign: callsign,
        registration: registration,
        aircraftType: aircraftType,
        altitudeFt: altitudeFt ?? this.altitudeFt,
        groundSpeedKt: groundSpeedKt,
        trackDeg: trackDeg,
        verticalRateFpm: verticalRateFpm,
        onGround: onGround,
        source: source,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'icao24': icao24,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'callsign': callsign,
        'registration': registration,
        'aircraftType': aircraftType,
        'altitudeFt': altitudeFt,
        'groundSpeedKt': groundSpeedKt,
        'trackDeg': trackDeg,
        'verticalRateFpm': verticalRateFpm,
        'onGround': onGround,
        'source': source,
      };

  static AircraftSample fromJson(Map<String, Object?> json) => AircraftSample(
        icao24: json['icao24'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        callsign: json['callsign'] as String?,
        registration: json['registration'] as String?,
        aircraftType: json['aircraftType'] as String?,
        altitudeFt: (json['altitudeFt'] as num?)?.toDouble(),
        groundSpeedKt: (json['groundSpeedKt'] as num?)?.toDouble(),
        trackDeg: (json['trackDeg'] as num?)?.toDouble(),
        verticalRateFpm: (json['verticalRateFpm'] as num?)?.toDouble(),
        onGround: json['onGround'] as bool? ?? false,
        source: json['source'] as String? ?? '',
      );
}

/// One position on an aircraft's flown path, stripped to what a map needs.
///
/// Separate from [AircraftSample] because a track is kept per *point* and a
/// snap can hold several tracks: repeating the callsign, registration, type and
/// source on every one of them would multiply the stored match by an order of
/// magnitude for fields that cannot change within a single flyover.
class TrackPoint {
  const TrackPoint({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.altitudeFt,
  });

  TrackPoint.of(AircraftSample sample)
      : time = sample.timestamp,
        latitude = sample.latitude,
        longitude = sample.longitude,
        altitudeFt = sample.altitudeFt;

  final DateTime time;
  final double latitude;
  final double longitude;
  final double? altitudeFt;

  /// A compact array, not an object. A busy sky puts several tracks of several
  /// dozen points each into one `match_json` column, and field names would be
  /// most of what is written.
  List<Object?> toJson() => <Object?>[
        time.toUtc().millisecondsSinceEpoch,
        latitude,
        longitude,
        altitudeFt,
      ];

  static TrackPoint fromJson(List<Object?> json) => TrackPoint(
        time: DateTime.fromMillisecondsSinceEpoch(
          (json[0] as num).toInt(),
          isUtc: true,
        ),
        latitude: (json[1] as num).toDouble(),
        longitude: (json[2] as num).toDouble(),
        altitudeFt: json.length > 3 ? (json[3] as num?)?.toDouble() : null,
      );
}

/// One aircraft as the live map sees it: where it is now, and where it has been
/// since the app started watching.
class AircraftTrack {
  const AircraftTrack({required this.latest, required this.points});

  /// The most recent position report.
  final AircraftSample latest;

  /// Oldest first, and only positions actually reported — the line drawn
  /// between them is a rendering convenience, not observed data.
  final List<TrackPoint> points;

  String get icao24 => latest.icao24;
}

/// Thins [points] to at most [maxPoints], keeping the ends and spreading the
/// rest evenly.
///
/// A five-minute recording polled every three seconds is a hundred reports per
/// aircraft, and at map scale the difference between a hundred and forty is
/// invisible. What is not invisible is the size of the JSON in the row, which
/// is read back every time the history list loads.
List<TrackPoint> decimateTrack(List<TrackPoint> points, int maxPoints) {
  if (maxPoints < 2 || points.length <= maxPoints) return points;
  final List<TrackPoint> out = <TrackPoint>[];
  final double step = (points.length - 1) / (maxPoints - 1);
  for (int i = 0; i < maxPoints; i++) {
    out.add(points[(i * step).round().clamp(0, points.length - 1)]);
  }
  return out;
}
