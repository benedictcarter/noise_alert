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
