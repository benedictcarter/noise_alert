import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:noise_alert/net/endpoints.dart';
import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/source.dart';

// OUTBOUND: auth.opensky-network.org, opensky-network.org
// Sends: the user's own OpenSky client id and secret to get a token, then a
// latitude/longitude box and that token. Nothing else, and nothing at all
// unless the user has entered credentials in Settings.

/// OpenSky Network client.
///
/// The only free source here that can answer "what was there a few minutes
/// ago", which is what makes back-filling a snap taken without a signal
/// possible. The retrospective window is one hour for a free account, so the
/// offline queue must be drained inside that hour or the chance is gone.
///
/// Authentication is OAuth2 client-credentials; username/password stopped
/// working in March 2026. Credentials are the user's own, entered in Settings
/// and stored on the device only.
class OpenSkySource implements AdsbSource {
  OpenSkySource({
    required this.clientId,
    required this.clientSecret,
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final http.Client _client;

  String? _accessToken;
  DateTime? _tokenExpiry;

  @override
  String get name => 'OpenSky';

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  @override
  Future<List<AircraftSample>> nearby({
    required double latitude,
    required double longitude,
    required double radiusNm,
  }) =>
      _states(latitude: latitude, longitude: longitude, radiusNm: radiusNm);

  @override
  Future<List<AircraftSample>> historical({
    required double latitude,
    required double longitude,
    required double radiusNm,
    required DateTime at,
  }) {
    final Duration age = DateTime.now().toUtc().difference(at.toUtc());
    if (age > const Duration(hours: 1)) {
      throw AdsbException(
        name,
        'Free OpenSky access only reaches one hour into the past; this snap is '
        '${age.inMinutes} minutes old.',
      );
    }
    return _states(
      latitude: latitude,
      longitude: longitude,
      radiusNm: radiusNm,
      at: at,
    );
  }

  Future<List<AircraftSample>> _states({
    required double latitude,
    required double longitude,
    required double radiusNm,
    DateTime? at,
  }) async {
    if (!isConfigured) {
      throw AdsbException(name, 'No OpenSky API client configured');
    }

    final double radiusM = radiusNm * kMetresPerNauticalMile;
    final double dLat = radiusM / 111320.0;
    final double dLon =
        radiusM / (111320.0 * math.max(0.01, math.cos(degToRad(latitude))));

    final Map<String, String> query = <String, String>{
      'lamin': (latitude - dLat).toStringAsFixed(4),
      'lamax': (latitude + dLat).toStringAsFixed(4),
      'lomin': (longitude - dLon).toStringAsFixed(4),
      'lomax': (longitude + dLon).toStringAsFixed(4),
      if (at != null)
        'time': (at.toUtc().millisecondsSinceEpoch ~/ 1000).toString(),
    };

    final Uri uri = Uri.parse('${Endpoints.openSkyApiBase}/states/all')
        .replace(queryParameters: query);

    final String token = await _token();
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{'Authorization': 'Bearer $token'},
    ).timeout(timeout);

    if (response.statusCode == 429) {
      throw AdsbException(name, 'Daily API credits exhausted');
    }
    if (response.statusCode != 200) {
      throw AdsbException(name, 'HTTP ${response.statusCode}');
    }

    return parseStates(response.body);
  }

  Future<String> _token() async {
    final DateTime? expiry = _tokenExpiry;
    final String? token = _accessToken;
    if (token != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return token;
    }

    final http.Response response = await _client.post(
      Uri.parse(Endpoints.openSkyTokenUrl),
      headers: <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded'
      },
      body: <String, String>{
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
      },
    ).timeout(timeout);

    if (response.statusCode != 200) {
      throw AdsbException(
          name, 'Token request failed (${response.statusCode})');
    }

    final Map<String, Object?> json =
        jsonDecode(response.body) as Map<String, Object?>;
    final String? access = json['access_token'] as String?;
    if (access == null) {
      throw AdsbException(name, 'Token response contained no access_token');
    }
    final int expiresIn = (json['expires_in'] as num?)?.toInt() ?? 1800;
    _accessToken = access;
    // Refresh a minute early rather than discovering expiry mid-snap.
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
    return access;
  }

  /// Exposed for tests. OpenSky state vectors are positional arrays:
  /// `[icao24, callsign, origin_country, time_position, last_contact,
  ///   longitude, latitude, baro_altitude, on_ground, velocity, true_track,
  ///   vertical_rate, sensors, geo_altitude, squawk, spi, position_source]`
  static List<AircraftSample> parseStates(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) return const <AircraftSample>[];
    final Object? states = decoded['states'];
    if (states is! List) return const <AircraftSample>[];

    final List<AircraftSample> out = <AircraftSample>[];
    for (final Object? row in states) {
      if (row is! List) continue;
      Object? at(int i) => i < row.length ? row[i] : null;

      final Object? icao = at(0);
      final Object? lon = at(5);
      final Object? lat = at(6);
      if (icao is! String || lat is! num || lon is! num) continue;

      final num? timePosition = at(3) as num?;
      final num? lastContact = at(4) as num?;
      final int epochSeconds = (timePosition ?? lastContact ?? 0).toInt();

      final num? geoAltitudeM = at(13) as num?;
      final num? baroAltitudeM = at(7) as num?;
      final num? altitudeM = geoAltitudeM ?? baroAltitudeM;

      final num? velocityMs = at(9) as num?;
      final num? verticalRateMs = at(11) as num?;

      out.add(
        AircraftSample(
          icao24: icao.trim().toLowerCase(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            epochSeconds * 1000,
            isUtc: true,
          ),
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          callsign: (at(1) as String?)?.trim(),
          altitudeFt:
              altitudeM == null ? null : altitudeM.toDouble() * kFeetPerMetre,
          groundSpeedKt: velocityMs == null
              ? null
              : velocityMs.toDouble() * 3600 / kMetresPerNauticalMile,
          trackDeg: (at(10) as num?)?.toDouble(),
          verticalRateFpm: verticalRateMs == null
              ? null
              : verticalRateMs.toDouble() * 60 * kFeetPerMetre,
          onGround: at(8) == true,
          source: 'OpenSky',
        ),
      );
    }
    return out;
  }

  void close() => _client.close();
}
