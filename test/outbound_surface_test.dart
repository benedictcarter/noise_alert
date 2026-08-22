import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The privacy boundary, asserted rather than promised.
///
/// The app's claim is that it has no backend and that five outbound services
/// exist, each deliberate. A claim like that survives exactly as long as the
/// next person to add a feature remembers it, so these tests hold the shape of
/// the code that makes it checkable: every network call is in `lib/net/`, and
/// every address the app can reach is in one file inside it.
///
/// If one of these fails, the fix is not to widen the allow-list. It is to
/// decide, deliberately, whether the app should be talking to something new,
/// and if it should, to put it in `lib/net/endpoints.dart` where a reviewer
/// will find it.
void main() {
  final List<File> libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  String rel(File f) => f.path.replaceAll(r'\', '/');

  bool inNet(File f) => rel(f).startsWith('lib/net/');

  test('lib is not empty, so a passing run means something', () {
    expect(libFiles.length, greaterThan(40));
  });

  test('only lib/net imports package:http', () {
    final List<String> offenders = <String>[
      for (final File f in libFiles)
        if (!inNet(f) && f.readAsStringSync().contains('package:http/'))
          rel(f),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'HTTP belongs in lib/net/ so the outbound surface stays greppable',
    );
  });

  test('every URL literal lives in lib/net/endpoints.dart', () {
    // Deliberately crude: any http:// or https:// in a Dart file at all,
    // comments included. A URL in a comment outside lib/net/ is still a hint
    // that a call moved, and the cost of the false positive is one line.
    final RegExp url = RegExp(r'https?://');
    final List<String> offenders = <String>[
      for (final File f in libFiles)
        if (rel(f) != 'lib/net/endpoints.dart' &&
            url.hasMatch(f.readAsStringSync()))
          rel(f),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'addresses belong in lib/net/endpoints.dart, all of them, so the '
          'list there is the whole list',
    );
  });

  test('endpoints.dart names five services and no more', () {
    final String source = File('lib/net/endpoints.dart').readAsStringSync();
    final Set<String> hosts = RegExp(r"'(?:https?://)?([a-z0-9.-]+\.[a-z]{2,})")
        .allMatches(source)
        .map((RegExpMatch m) => m.group(1)!)
        .toSet();
    expect(
      hosts,
      <String>{
        'api.adsb.lol',
        'api.airplanes.live',
        'auth.opensky-network.org',
        'opensky-network.org',
        'tiles.openfreemap.org',
        'api.postcodes.io',
      },
      reason: 'six hosts across five services. Adding one is a decision: '
          'update CLAUDE.md and REVIEW.md in the same commit as this list',
    );
  });

  test('every file that can reach the network says so at the top', () {
    // The banner is what a reviewer greps for, so it has to be on the files
    // that need it and nowhere else. The map files earn one without importing
    // http at all, because native MapLibre fetches their tiles.
    final List<String> expected = <String>[
      'lib/letter/sender.dart',
      'lib/map/live_map.dart',
      'lib/map/snapshot_host.dart',
      'lib/net/client.dart',
      'lib/net/live_adsb.dart',
      'lib/net/opensky.dart',
      'lib/net/postcodes.dart',
    ];
    final List<String> found = <String>[
      for (final File f in libFiles)
        if (f.readAsStringSync().contains('\n// OUTBOUND:') ||
            f.readAsStringSync().startsWith('// OUTBOUND:'))
          rel(f),
    ];
    expect(found, expected);
  });

  test('nothing in the app phones home', () {
    // No analytics, no crash reporter, no backend. These are the packages that
    // would bring one in, and pubspec is where they would appear.
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    for (final String banned in <String>[
      'firebase',
      'sentry',
      'analytics',
      'crashlytics',
      'amplitude',
      'mixpanel',
      'posthog',
      'datadog',
    ]) {
      expect(
        pubspec.toLowerCase().contains(banned),
        isFalse,
        reason: 'no telemetry: $banned',
      );
    }
  });
}
