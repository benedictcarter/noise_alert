import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/flights/config.dart';
import 'package:noise_alert/snap/snap_service.dart';
import 'package:noise_alert/mic/metrics.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';
import 'package:noise_alert/snap/snap.dart';

final DateTime _heardAt = DateTime(2026, 8, 20, 14, 49, 33);

AircraftSample _aircraft(String icao) => AircraftSample(
      icao24: icao,
      timestamp: _heardAt,
      latitude: 51.5,
      longitude: -0.1,
      callsign: 'BAW$icao',
      altitudeFt: 3000,
      source: 'adsb.lol',
    );

FlightCandidate _candidate(String icao, double horizontalM) => FlightCandidate(
      aircraft: _aircraft(icao),
      closestApproachTime: _heardAt,
      slantRangeM: horizontalM + 300,
      horizontalRangeM: horizontalM,
      heightAboveObserverM: 900,
      elevationDegrees: 40,
      score: 0.8,
      extrapolated: false,
    );

Snap _snap(List<FlightCandidate> candidates) => Snap(
      id: 'snap-1',
      recordedAt: _heardAt,
      latitude: 51.50012,
      longitude: -0.10034,
      metrics: const AcousticMetrics.unmeasured(),
      status: SnapStatus.awaitingReview,
      match: candidates.isEmpty
          ? FlightMatch.none(searchedFrom: _heardAt, searchedTo: _heardAt)
          : FlightMatch(
              candidates: candidates,
              confidence: 0.8,
              searchedFrom: _heardAt,
              searchedTo: _heardAt,
            ),
      deviceModel: 'Google Pixel 8',
      osVersion: 'Android 15 (SDK 35)',
      appVersion: '0.1.0+1',
    );

void main() {
  group('STOP & SEND decides whether there is anything left to ask', () {
    test('an aircraft plainly overhead is named without a tap', () {
      final Snap out = SnapService.autoConfirm(_snap(<FlightCandidate>[
        _candidate('abc123', 250),
      ]));

      expect(out.selectedIcao24, 'abc123');
      expect(out.status, SnapStatus.confirmed);
      expect(out.confirmedCandidate, isNotNull);
    });

    test('the boundary itself counts as overhead', () {
      // Deliberately inclusive: a candidate sitting exactly on the threshold
      // should not flip behaviour on a rounding error in the geometry.
      final Snap out = SnapService.autoConfirm(_snap(<FlightCandidate>[
        _candidate('abc123', MatchConfig.autoConfirmMaxHorizontalM),
      ]));

      expect(out.selectedIcao24, 'abc123');
    });

    test('a candidate out on the ground track is left for the user', () {
      // This is the case the review screen exists for. A jet a kilometre and a
      // half away horizontally may well be the one that was heard, or may be
      // one of three, and the app has no business picking.
      final Snap out = SnapService.autoConfirm(_snap(<FlightCandidate>[
        _candidate('abc123', MatchConfig.autoConfirmMaxHorizontalM + 1),
        _candidate('def456', 4000),
      ]));

      expect(out.selectedIcao24, isNull);
      expect(out.status, SnapStatus.awaitingReview);
      expect(out.match!.hasCandidates, isTrue);
    });

    test('no candidates at all leaves nothing to adjudicate', () {
      // Not a failure. A letter saying an aircraft was audible at this address
      // at this time is a complaint in its own right, so the send path marks
      // the aircraft unidentified rather than stopping to ask.
      final Snap out = SnapService.autoConfirm(_snap(<FlightCandidate>[]));

      expect(out.selectedIcao24, isNull);
      expect(out.match!.hasCandidates, isFalse);
    });
  });
}
