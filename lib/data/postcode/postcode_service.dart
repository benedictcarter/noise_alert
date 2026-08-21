import 'dart:convert';

import 'package:http/http.dart' as http;

/// What a postcode turned out to be.
class PostcodeResult {
  const PostcodeResult({
    required this.postcode,
    required this.town,
  });

  /// The postcode as the Royal Mail writes it, spacing and all. Worth taking
  /// even when nothing else is: someone who typed "tw61ap" gets "TW6 1AP" back
  /// and their letter stops looking like it was written in a hurry.
  final String postcode;

  /// The local authority the postcode sits in: "Hounslow", "Windsor and
  /// Maidenhead".
  ///
  /// Deliberately the council area rather than the post town, which this data
  /// set does not carry anyway. For a complaint it is the better of the two:
  /// it is the council whose area the noise is landing in, and therefore the
  /// body being written to.
  final String town;
}

/// Turns a UK postcode into a town, so an older user types two fields instead
/// of five.
///
/// This is the one thing in the app that sends anything anywhere on the user's
/// behalf, and it only happens when they press the button. A postcode is a lot
/// less than the app already hands adsb.lol: that gets the coordinates of the
/// spot they are standing on, to five decimal places.
///
/// postcodes.io is a free, key-less front end to the ONS Postcode Directory,
/// which is open government data. There is no account, no quota to run out
/// mid-complaint, and nothing about the user in the request beyond the
/// postcode itself.
class PostcodeService {
  PostcodeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _host = 'api.postcodes.io';

  /// Loose enough to catch every real UK postcode and reject an obvious typo
  /// before it costs a round trip. Deliberately not strict: the authority on
  /// whether a postcode exists is the lookup, not a regular expression.
  static final RegExp _shape =
      RegExp(r'^[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}$', caseSensitive: false);

  static bool looksLikeAPostcode(String value) => _shape.hasMatch(value.trim());

  /// Null when the postcode does not exist, or when the lookup could not be
  /// reached.
  ///
  /// The caller cannot do anything different in those two cases and neither
  /// can the user, so they are not distinguished: the screen says it could not
  /// check and lets them carry on typing. A postcode that fails to verify is
  /// still a postcode, and a complaint is never blocked on one.
  Future<PostcodeResult?> lookup(String postcode) async {
    final String trimmed = postcode.trim();
    if (!looksLikeAPostcode(trimmed)) return null;

    try {
      final Uri uri = Uri.https(
          _host,
          '/postcodes/${Uri.encodeComponent(
            trimmed.toUpperCase(),
          )}');
      final http.Response response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) return null;
      final Object? result = decoded['result'];
      if (result is! Map<String, Object?>) return null;

      // admin_district is populated for every UK postcode. The others are not:
      // London boroughs and unitary authorities have no admin_county, and
      // parish is null across most of Scotland. Fall back down the chain
      // rather than showing an empty box that looks like a failure.
      final String town = _firstNonEmpty(<Object?>[
        result['admin_district'],
        result['admin_county'],
        result['region'],
      ]);
      if (town.isEmpty) return null;

      return PostcodeResult(
        postcode: _firstNonEmpty(<Object?>[result['postcode']]).isEmpty
            ? trimmed.toUpperCase()
            : result['postcode']! as String,
        town: town,
      );
    } on Object {
      // Offline, DNS down, postcodes.io having a bad day. None of it is the
      // user's problem and none of it stops them complaining.
      return null;
    }
  }

  static String _firstNonEmpty(List<Object?> candidates) {
    for (final Object? c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return '';
  }

  void dispose() => _client.close();
}
