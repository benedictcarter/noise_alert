
import 'package:flutter_test/flutter_test.dart';

import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/lookup.dart';
import 'package:noise_alert/flights/watch.dart';
import 'package:noise_alert/map/nearby.dart';
import 'package:noise_alert/where/location.dart';

/// Counts what [SkyWatch] asks of the lookup service without going near a
/// timer, a network call or a real poll.
class _FakeLookup extends FlightLookupService {
  _FakeLookup() : super(liveSources: const <Never>[]);

  final List<(double, double)> centres = <(double, double)>[];
  int stops = 0;
  bool _tracking = false;

  @override
  bool get isTracking => _tracking;

  @override
  void startTracking({required double latitude, required double longitude}) {
    centres.add((latitude, longitude));
    _tracking = true;
  }

  @override
  void stopTracking() {
    stops++;
    _tracking = false;
  }
}

class _FakeLocation extends LocationService {
  const _FakeLocation({this.fix, this.status, this.throws = false});

  final SnapLocation? fix;
  final LocationStatus? status;

  /// A receiver that cannot produce a fix: indoors, or the deadline missed.
  final bool throws;

  @override
  Future<LocationStatus> check() async =>
      status ?? const LocationStatus(LocationAvailability.ready);

  @override
  Future<SnapLocation> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (throws) throw LocationUnavailable('no fix');
    return fix!;
  }
}

/// Kew Bridge, and a point 5 km away.
const SnapLocation _home = SnapLocation(latitude: 51.4875, longitude: -0.2890);
const SnapLocation _nextStreet =
    SnapLocation(latitude: 51.4880, longitude: -0.2890);
const SnapLocation _acrossTown =
    SnapLocation(latitude: 51.5320, longitude: -0.2890);

SkyWatch _watch(_FakeLookup lookup, {LocationService? location}) => SkyWatch(
      lookup: lookup,
      location: location ?? const _FakeLocation(fix: _home),
      tick: const Duration(milliseconds: 5),
      refixInterval: const Duration(hours: 1),
    );

/// Long enough for several ticks of the watch above.
Future<void> _ticks() => Future<void>.delayed(const Duration(milliseconds: 40));

AircraftTrack _at(String icao, double lat, double lon) => AircraftTrack(
      latest: AircraftSample(
        icao24: icao,
        timestamp: DateTime.utc(2026, 1, 1),
        latitude: lat,
        longitude: lon,
      ),
      points: const <TrackPoint>[],
    );

void main() {
  group('SkyWatch', () {
    test('polls the sky as soon as it is started, with no recording involved',
        () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch = _watch(lookup);

      watch.start();
      await _ticks();

      expect(lookup.isTracking, isTrue);
      expect(watch.observer?.latitude, _home.latitude);
      watch.dispose();
    });

    test('a poll stopped by anything at all is back within a tick', () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch = _watch(lookup);
      watch.start();
      await _ticks();

      // Whatever did this. A discarded recording used to; the point of the
      // clause under test is that this file does not have to know.
      lookup.stopTracking();
      expect(lookup.isTracking, isFalse);

      await _ticks();
      expect(lookup.isTracking, isTrue);
      watch.dispose();
    });

    test('leaving the app stops it, and it stays stopped', () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch = _watch(lookup);
      watch.start();
      await _ticks();

      watch.stop();
      expect(lookup.isTracking, isFalse);
      expect(watch.isWatching, isFalse);

      await _ticks();
      expect(lookup.isTracking, isFalse);
      watch.dispose();
    });

    test('re-centres the query when the user has really moved, not otherwise',
        () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch = _watch(lookup);
      watch.start();
      await _ticks();
      expect(lookup.centres, hasLength(1));

      watch.offer(_nextStreet);
      expect(lookup.centres, hasLength(1), reason: 'a few hundred metres');

      watch.offer(_acrossTown);
      expect(lookup.centres, hasLength(2), reason: 'five kilometres');
      watch.dispose();
    });

    test('a fix from a capture is taken rather than paid for twice', () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch =
          _watch(lookup, location: const _FakeLocation(throws: true));
      watch.start();
      await _ticks();
      expect(lookup.isTracking, isFalse, reason: 'no fix of its own');

      watch.offer(_home);
      expect(lookup.isTracking, isTrue);
      expect(watch.observer?.longitude, _home.longitude);
      watch.dispose();
    });

    test('a backgrounded watch ignores a fix offered to it', () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch =
          _watch(lookup, location: const _FakeLocation(throws: true));
      watch.start();
      await _ticks();

      watch.stop();
      watch.offer(_home);

      expect(lookup.isTracking, isFalse);
      watch.dispose();
    });

    test('falls back to the last known fix rather than drawing nothing',
        () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch = _watch(
        lookup,
        location: const _FakeLocation(
          status: LocationStatus(
            LocationAvailability.denied,
            lastFix: _home,
          ),
        ),
      );

      watch.start();
      await _ticks();

      expect(watch.observer?.latitude, _home.latitude);
      expect(lookup.isTracking, isTrue);
      watch.dispose();
    });

    test('renews the fix on the stream, for a map that is watching it',
        () async {
      final _FakeLookup lookup = _FakeLookup();
      final SkyWatch watch =
          _watch(lookup, location: const _FakeLocation(throws: true));
      watch.start();

      final Future<SnapLocation> next = watch.observerStream.first;
      watch.offer(_home);

      expect((await next).latitude, _home.latitude);
      watch.dispose();
    });
  });

  group('nearbyTracks', () {
    test('draws what is overhead and drops what is a county away', () {
      final List<AircraftTrack> tracks = <AircraftTrack>[
        _at('aaa111', 51.4880, -0.2890), // yards away
        _at('bbb222', 51.5100, -0.2890), // about 2.5 km
        _at('ccc333', 51.5320, -0.2890), // just inside five
        _at('ddd444', 51.6000, -0.2890), // about 12.5 km
      ];

      expect(
        nearbyTracks(tracks, _home).map((AircraftTrack t) => t.icao24),
        <String>['aaa111', 'bbb222', 'ccc333'],
      );
    });

    test('draws nothing at all without a fix to measure from', () {
      expect(nearbyTracks(<AircraftTrack>[_at('aaa111', 51.4880, -0.2890)], null),
          isEmpty);
    });
  });
}
