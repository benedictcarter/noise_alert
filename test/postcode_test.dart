import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noise_alert/data/postcode/postcode_service.dart';
import 'package:noise_alert/domain/profile.dart';

/// A postcodes.io reply, trimmed to the fields the service reads.
String _body({
  String postcode = 'TW6 1AP',
  Object? district = 'Hounslow',
  Object? county,
  Object? region = 'London',
}) =>
    jsonEncode(<String, Object?>{
      'status': 200,
      'result': <String, Object?>{
        'postcode': postcode,
        'admin_district': district,
        'admin_county': county,
        'region': region,
      },
    });

PostcodeService _serving(
  Future<http.Response> Function(http.Request) handler,
) =>
    PostcodeService(client: MockClient(handler));

void main() {
  group('what counts as a postcode', () {
    test('the shapes people actually type are all accepted', () {
      for (final String value in <String>[
        'TW6 1AP',
        'tw6 1ap',
        'TW61AP',
        '  W1A 0AX  ',
        'EC1A 1BB',
        'B33 8TH',
        'DN55 1PT',
      ]) {
        expect(PostcodeService.looksLikeAPostcode(value), isTrue,
            reason: value);
      }
    });

    test('half a postcode is not one', () {
      for (final String value in <String>['TW6', '', 'Hounslow', '1AP']) {
        expect(PostcodeService.looksLikeAPostcode(value), isFalse,
            reason: value);
      }
    });
  });

  group('the lookup', () {
    test('returns the council area, and the postcode properly spaced',
        () async {
      late Uri asked;
      final PostcodeService service = _serving((http.Request r) async {
        asked = r.url;
        return http.Response(_body(), 200);
      });

      final PostcodeResult? result = await service.lookup('tw61ap');

      expect(result?.town, 'Hounslow');
      expect(result?.postcode, 'TW6 1AP');
      expect(asked.host, 'api.postcodes.io');
      expect(asked.path, '/postcodes/TW61AP');
    });

    test('a postcode with no district falls back to the county', () async {
      final PostcodeService service = _serving((http.Request _) async =>
          http.Response(_body(district: null, county: 'Kent'), 200));

      expect((await service.lookup('ME1 1AA'))?.town, 'Kent');
    });

    test('and to the region when there is no county either', () async {
      final PostcodeService service = _serving((http.Request _) async =>
          http.Response(
              _body(district: '  ', county: null, region: 'South East'), 200));

      expect((await service.lookup('ME1 1AA'))?.town, 'South East');
    });

    test('a postcode that does not exist is simply null', () async {
      final PostcodeService service = _serving(
          (http.Request _) async => http.Response('{"status":404}', 404));

      expect(await service.lookup('ZZ1 1ZZ'), isNull);
    });

    test('an unreachable server is null too, not an exception', () async {
      // The whole point: a lookup that fails must never stop a complaint, so
      // it cannot throw into the widget that called it.
      final PostcodeService service =
          _serving((http.Request _) async => throw const HttpExceptionStub());

      expect(await service.lookup('TW6 1AP'), isNull);
    });

    test('rubbish in the box costs no round trip at all', () async {
      bool called = false;
      final PostcodeService service = _serving((http.Request _) async {
        called = true;
        return http.Response(_body(), 200);
      });

      expect(await service.lookup('somewhere near the airport'), isNull);
      expect(called, isFalse);
    });

    test('nonsense JSON is null rather than a crash', () async {
      final PostcodeService service = _serving(
          (http.Request _) async => http.Response('not json at all', 200));

      expect(await service.lookup('TW6 1AP'), isNull);
    });
  });

  group('what a complaint actually needs', () {
    test('a name and a postcode, and nothing else', () {
      const ComplainantProfile profile = ComplainantProfile(
        fullName: 'A Resident',
        postcode: 'TW6 1AP',
      );

      expect(profile.isComplete, isTrue);
    });

    test('the house number and the street are not required', () {
      const ComplainantProfile profile = ComplainantProfile(
        fullName: 'A Resident',
        postcode: 'TW6 1AP',
        addressLine1: '',
        town: '',
        phone: '',
      );

      expect(profile.isComplete, isTrue);
    });

    test('but a name on its own is not enough, nor a postcode on its own', () {
      expect(
        const ComplainantProfile(fullName: 'A Resident').isComplete,
        isFalse,
      );
      expect(
        const ComplainantProfile(postcode: 'TW6 1AP').isComplete,
        isFalse,
      );
      expect(
        const ComplainantProfile(fullName: '   ', postcode: '  ').isComplete,
        isFalse,
      );
    });
  });
}

/// Stands in for whatever the socket throws when there is no network. The
/// service catches `Object`, so the exact type is beside the point.
class HttpExceptionStub implements Exception {
  const HttpExceptionStub();
}
