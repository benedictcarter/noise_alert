import '../../domain/aircraft.dart';

/// A source of live aircraft positions.
///
/// Kept deliberately small so sources are swappable: adsb.lol has said it may
/// introduce API keys, and the whole matcher must survive that without changes.
abstract class AdsbSource {
  String get name;

  /// Aircraft currently within [radiusNm] of the point.
  Future<List<AircraftSample>> nearby({
    required double latitude,
    required double longitude,
    required double radiusNm,
  });

  /// Aircraft near the point at a past instant.
  ///
  /// Most free feeds are live-only and should return an empty list; OpenSky is
  /// the exception and can serve the last hour, which is what makes offline
  /// back-fill possible.
  Future<List<AircraftSample>> historical({
    required double latitude,
    required double longitude,
    required double radiusNm,
    required DateTime at,
  }) async =>
      const <AircraftSample>[];
}

class AdsbException implements Exception {
  AdsbException(this.source, this.message);

  final String source;
  final String message;

  @override
  String toString() => 'AdsbException($source): $message';
}
