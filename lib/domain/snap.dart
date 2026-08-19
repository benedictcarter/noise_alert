import 'dart:convert';

import 'acoustic_metrics.dart';
import 'aircraft.dart';
import 'flight_match.dart';

enum SnapStatus {
  /// Captured; no flight lookup has succeeded yet.
  unmatched,

  /// Candidates found, awaiting the user's confirmation.
  awaitingReview,

  /// User has confirmed which aircraft (or explicitly chosen "unidentified").
  confirmed,

  /// Handed to the mail composer and marked sent by the user.
  sent,
}

/// Everything captured for one noise event.
class Snap {
  const Snap({
    required this.id,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    required this.metrics,
    required this.status,
    this.gpsAccuracyM,
    this.gpsAltitudeM,
    this.clipPath,
    this.attachClip = false,
    this.match,
    this.selectedIcao24,
    this.unidentifiedAircraft = false,
    this.sentAt,
    this.deviceModel = '',
    this.osVersion = '',
    this.appVersion = '',
    this.notes = '',
  });

  final String id;

  /// Wall-clock time of the button press, i.e. when the noise was *heard*.
  /// The aircraft's closest approach was earlier — see [FlightMatch].
  final DateTime recordedAt;

  final double latitude;
  final double longitude;
  final double? gpsAccuracyM;
  final double? gpsAltitudeM;

  final AcousticMetrics metrics;
  final SnapStatus status;

  /// Path to the saved WAV clip, if one was kept.
  final String? clipPath;

  /// Whether to attach [clipPath] to the complaint. Independent of whether the
  /// clip exists: the user can keep a clip for their own records and still not
  /// send it.
  final bool attachClip;

  final FlightMatch? match;

  /// The aircraft the user confirmed. Null plus [unidentifiedAircraft] false
  /// means nothing has been confirmed and no complaint may name a flight.
  final String? selectedIcao24;

  /// The user looked at the candidates and decided none of them fit, or chose
  /// to complain without naming a flight.
  final bool unidentifiedAircraft;

  final DateTime? sentAt;

  /// Recorded so the recipient can judge the measurement for themselves. There
  /// is no calibration certificate behind a phone microphone; the make, model
  /// and OS version are the next best thing.
  final String deviceModel;
  final String osVersion;
  final String appVersion;

  final String notes;

  AircraftSample? get confirmedAircraft {
    final String? id = selectedIcao24;
    if (id == null) return null;
    final FlightMatch? m = match;
    if (m == null) return null;
    for (final FlightCandidate c in m.candidates) {
      if (c.aircraft.icao24 == id) return c.aircraft;
    }
    return null;
  }

  FlightCandidate? get confirmedCandidate {
    final String? id = selectedIcao24;
    final FlightMatch? m = match;
    if (id == null || m == null) return null;
    for (final FlightCandidate c in m.candidates) {
      if (c.aircraft.icao24 == id) return c;
    }
    return null;
  }

  /// A complaint may only be composed once the user has resolved the aircraft
  /// question one way or the other.
  bool get isReadyToSend => selectedIcao24 != null || unidentifiedAircraft;

  Snap copyWith({
    SnapStatus? status,
    String? clipPath,
    bool? attachClip,
    FlightMatch? match,
    String? selectedIcao24,
    bool? unidentifiedAircraft,
    DateTime? sentAt,
    String? notes,
    bool clearSelection = false,
  }) =>
      Snap(
        id: id,
        recordedAt: recordedAt,
        latitude: latitude,
        longitude: longitude,
        gpsAccuracyM: gpsAccuracyM,
        gpsAltitudeM: gpsAltitudeM,
        metrics: metrics,
        status: status ?? this.status,
        clipPath: clipPath ?? this.clipPath,
        attachClip: attachClip ?? this.attachClip,
        match: match ?? this.match,
        selectedIcao24:
            clearSelection ? null : (selectedIcao24 ?? this.selectedIcao24),
        unidentifiedAircraft: unidentifiedAircraft ?? this.unidentifiedAircraft,
        sentAt: sentAt ?? this.sentAt,
        deviceModel: deviceModel,
        osVersion: osVersion,
        appVersion: appVersion,
        notes: notes ?? this.notes,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'recorded_at': recordedAt.toUtc().millisecondsSinceEpoch,
        'latitude': latitude,
        'longitude': longitude,
        'gps_accuracy_m': gpsAccuracyM,
        'gps_altitude_m': gpsAltitudeM,
        'metrics_json': jsonEncode(metrics.toJson()),
        'status': status.name,
        'clip_path': clipPath,
        'attach_clip': attachClip ? 1 : 0,
        'match_json': match == null ? null : jsonEncode(encodeMatch(match!)),
        'selected_icao24': selectedIcao24,
        'unidentified': unidentifiedAircraft ? 1 : 0,
        'sent_at': sentAt?.toUtc().millisecondsSinceEpoch,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'notes': notes,
      };

  static Snap fromRow(Map<String, Object?> row) {
    final String? matchJson = row['match_json'] as String?;
    return Snap(
      id: row['id'] as String,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        row['recorded_at'] as int,
        isUtc: true,
      ).toLocal(),
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      gpsAccuracyM: (row['gps_accuracy_m'] as num?)?.toDouble(),
      gpsAltitudeM: (row['gps_altitude_m'] as num?)?.toDouble(),
      metrics: AcousticMetrics.fromJson(
        jsonDecode(row['metrics_json'] as String) as Map<String, Object?>,
      ),
      status: SnapStatus.values.firstWhere(
        (SnapStatus s) => s.name == row['status'],
        orElse: () => SnapStatus.unmatched,
      ),
      clipPath: row['clip_path'] as String?,
      attachClip: (row['attach_clip'] as int? ?? 0) == 1,
      match: matchJson == null
          ? null
          : decodeMatch(jsonDecode(matchJson) as Map<String, Object?>),
      selectedIcao24: row['selected_icao24'] as String?,
      unidentifiedAircraft: (row['unidentified'] as int? ?? 0) == 1,
      sentAt: row['sent_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['sent_at'] as int,
                  isUtc: true)
              .toLocal(),
      deviceModel: row['device_model'] as String? ?? '',
      osVersion: row['os_version'] as String? ?? '',
      appVersion: row['app_version'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
    );
  }
}

Map<String, Object?> encodeMatch(FlightMatch match) => <String, Object?>{
      'confidence': match.confidence,
      'searchedFrom': match.searchedFrom.toUtc().toIso8601String(),
      'searchedTo': match.searchedTo.toUtc().toIso8601String(),
      'selectedIcao24': match.selectedIcao24,
      'note': match.note,
      'candidates': match.candidates
          .map(
            (FlightCandidate c) => <String, Object?>{
              'aircraft': c.aircraft.toJson(),
              'closestApproachTime':
                  c.closestApproachTime.toUtc().toIso8601String(),
              'slantRangeM': c.slantRangeM,
              'horizontalRangeM': c.horizontalRangeM,
              'heightAboveObserverM': c.heightAboveObserverM,
              'elevationDegrees': c.elevationDegrees,
              'score': c.score,
              'extrapolated': c.extrapolated,
            },
          )
          .toList(),
    };

FlightMatch decodeMatch(Map<String, Object?> json) => FlightMatch(
      candidates: ((json['candidates'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()
          .map(
            (Map<String, Object?> c) => FlightCandidate(
              aircraft: AircraftSample.fromJson(
                  c['aircraft'] as Map<String, Object?>),
              closestApproachTime:
                  DateTime.parse(c['closestApproachTime'] as String),
              slantRangeM: (c['slantRangeM'] as num).toDouble(),
              horizontalRangeM: (c['horizontalRangeM'] as num).toDouble(),
              heightAboveObserverM:
                  (c['heightAboveObserverM'] as num).toDouble(),
              elevationDegrees: (c['elevationDegrees'] as num).toDouble(),
              score: (c['score'] as num).toDouble(),
              extrapolated: c['extrapolated'] as bool? ?? false,
            ),
          )
          .toList(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      searchedFrom: DateTime.parse(json['searchedFrom'] as String),
      searchedTo: DateTime.parse(json['searchedTo'] as String),
      selectedIcao24: json['selectedIcao24'] as String?,
      note: json['note'] as String?,
    );
