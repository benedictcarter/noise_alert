import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:noise_alert/net/endpoints.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/source.dart';

// OUTBOUND: api.adsb.lol, api.airplanes.live
// Sends: a latitude, a longitude and a search radius, every 3 s while a
// recording is running. Nothing that identifies the user or the device.

/// What is in the sky right now, from the free community ADS-B feeds.
///
/// One class serves both adsb.lol and airplanes.live because both speak the
/// readsb/tar1090 `aircraft.json` schema. That is what "tar1090" means
/// wherever it appears below: a wire format, not a service, and not a name
/// worth putting on a class.
///
/// Both are free, need no key today, and are live-only: they answer "what is
/// overhead now" and nothing about a minute ago, which is what [OpenSkySource]
/// is for. Both ask for no more than about one request per second, which the
/// polling interval respects.
class LiveAdsbSource implements AdsbSource {
  LiveAdsbSource({
    required this.name,
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  factory LiveAdsbSource.adsbLol({http.Client? client}) => LiveAdsbSource(
        name: 'adsb.lol',
        baseUrl: Endpoints.adsbLolBase,
        client: client,
      );

  factory LiveAdsbSource.airplanesLive({http.Client? client}) => LiveAdsbSource(
        name: 'airplanes.live',
        baseUrl: Endpoints.airplanesLiveBase,
        client: client,
      );

  @override
  final String name;

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<List<AircraftSample>> historical({
    required double latitude,
    required double longitude,
    required double radiusNm,
    required DateTime at,
  }) async =>
      const <AircraftSample>[];

  @override
  Future<List<AircraftSample>> nearby({
    required double latitude,
    required double longitude,
    required double radiusNm,
  }) async {
    final Uri uri = Uri.parse(
      '$baseUrl/point/${latitude.toStringAsFixed(6)}/'
      '${longitude.toStringAsFixed(6)}/${radiusNm.round()}',
    );

    final http.Response response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw AdsbException(name, 'HTTP ${response.statusCode}');
    }

    return parse(response.body, name);
  }

  /// Exposed for tests against recorded fixtures.
  static List<AircraftSample> parse(String body, String sourceName) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw AdsbException(sourceName, 'Unexpected response shape');
    }

    final DateTime now = _parseNow(decoded['now']);
    final Object? list = decoded['ac'] ?? decoded['aircraft'];
    if (list is! List) return const <AircraftSample>[];

    final List<AircraftSample> out = <AircraftSample>[];
    for (final Object? item in list) {
      if (item is! Map<String, Object?>) continue;
      final AircraftSample? sample = _parseAircraft(item, now, sourceName);
      if (sample != null) out.add(sample);
    }
    return out;
  }

  /// `now` is seconds in tar1090's own output but milliseconds in some hosted
  /// variants. Distinguish by magnitude rather than trusting either.
  static DateTime _parseNow(Object? raw) {
    if (raw is num) {
      final double v = raw.toDouble();
      final int ms = v > 1e12 ? v.round() : (v * 1000).round();
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    return DateTime.now().toUtc();
  }

  static AircraftSample? _parseAircraft(
    Map<String, Object?> a,
    DateTime now,
    String sourceName,
  ) {
    final Object? hex = a['hex'];
    final Object? lat = a['lat'];
    final Object? lon = a['lon'];
    if (hex is! String || lat is! num || lon is! num) return null;

    // `alt_baro` is the string "ground" for aircraft on the surface.
    final Object? altBaro = a['alt_baro'];
    final bool onGround = altBaro == 'ground';

    // Prefer geometric (GNSS) altitude: barometric altitude is referenced to
    // the standard pressure setting above the transition altitude and can be
    // a few hundred feet out, which matters for a 900 ft overflight.
    final double? altitudeFt = _asDouble(a['alt_geom']) ??
        (altBaro is num ? altBaro.toDouble() : null);

    final double seenPos = _asDouble(a['seen_pos']) ?? 0;
    final DateTime timestamp =
        now.subtract(Duration(milliseconds: (seenPos * 1000).round()));

    return AircraftSample(
      icao24: hex.trim().toLowerCase(),
      timestamp: timestamp,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      callsign: (a['flight'] as String?)?.trim(),
      registration: (a['r'] as String?)?.trim(),
      aircraftType: (a['t'] as String?)?.trim(),
      altitudeFt: altitudeFt,
      groundSpeedKt: _asDouble(a['gs']),
      trackDeg: _asDouble(a['track']),
      verticalRateFpm: _asDouble(a['geom_rate']) ?? _asDouble(a['baro_rate']),
      onGround: onGround,
      source: sourceName,
    );
  }

  static double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

  void close() => _client.close();
}
