import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/data/storage/database.dart';
import 'package:noise_alert/domain/acoustic_metrics.dart';
import 'package:noise_alert/domain/aircraft.dart';
import 'package:noise_alert/domain/flight_match.dart';
import 'package:noise_alert/domain/profile.dart';
import 'package:noise_alert/domain/settings.dart';
import 'package:noise_alert/domain/snap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const AcousticMetrics _metrics = AcousticMetrics(
  laEqDb: 68.2,
  laMaxDb: 78.4,
  ambientLa90Db: 38.1,
  peakWindowLaEqDb: 71.9,
  peakWindowStartMs: 24000,
  peakWindowDurationMs: 10000,
  eventDurationMs: 50000,
  clipped: false,
  calibrated: false,
  calibrationOffsetDb: 120,
  sampleRate: 48000,
);

Snap _snap({
  required String id,
  required DateTime at,
  SnapStatus status = SnapStatus.unmatched,
}) =>
    Snap(
      id: id,
      recordedAt: at,
      latitude: 51.50012,
      longitude: -0.10034,
      gpsAccuracyM: 8,
      metrics: _metrics,
      status: status,
      deviceModel: 'Google Pixel 8',
      osVersion: 'Android 15 (SDK 35)',
      appVersion: '0.1.0+1',
    );

void main() {
  // sqflite has no desktop implementation; the ffi one runs the real SQLite,
  // so these are genuine round trips through SQL rather than a fake.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(overridePath: inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  test('an empty database hands back the defaults, not null', () async {
    // main() reads these before the first frame, so a fresh install must not
    // need a null check at every call site.
    expect(await db.loadProfile(), const ComplainantProfile());
    expect((await db.loadSettings()).templateSubject, isNotEmpty);
    expect(await db.allSnaps(), isEmpty);
  });

  test('the profile survives a write and a reopen', () async {
    const ComplainantProfile profile = ComplainantProfile(
      fullName: 'A Resident',
      addressLine1: '1 Quiet Lane',
      town: 'Someton',
      postcode: 'AB1 2CD',
      email: 'resident@example.com',
      phone: '01234 567890',
    );
    await db.saveProfile(profile);

    expect(await db.loadProfile(), profile);

    // Saving again must update in place rather than fail on the primary key.
    await db.saveProfile(profile.copyWith(town: 'Elsewhere'));
    expect((await db.loadProfile()).town, 'Elsewhere');
  });

  test('settings round-trip, including the edited letter and recipients',
      () async {
    const AppSettings settings = AppSettings(
      keepClip: true,
      attachClipByDefault: true,
      calibrationOffsetDb: 117.5,
      calibrated: true,
      templateSubject: 'Custom subject',
      templateBody: 'Custom body with {laMax}.',
      openSkyClientId: 'client-id',
      recipientSets: <RecipientSet>[
        RecipientSet(
          id: 'default',
          label: 'Heathrow',
          to: <String>['noise@example.com'],
          cc: <String>['group@example.com'],
        ),
      ],
    );
    await db.saveSettings(settings);

    final AppSettings back = await db.loadSettings();
    expect(back.keepClip, isTrue);
    expect(back.calibrationOffsetDb, 117.5);
    expect(back.calibrated, isTrue);
    expect(back.templateBody, 'Custom body with {laMax}.');
    expect(back.openSkyClientId, 'client-id');
    expect(back.recipientSets.single.label, 'Heathrow');
    expect(back.recipientSets.single.to, <String>['noise@example.com']);
  });

  test('a snap round-trips through SQL with its metrics and match intact',
      () async {
    final DateTime at = DateTime(2026, 8, 19, 21, 14, 30);
    final AircraftSample aircraft = AircraftSample(
      icao24: 'abc123',
      timestamp: at.subtract(const Duration(seconds: 5)),
      latitude: 51.5,
      longitude: -0.1,
      callsign: 'BAW123',
      registration: 'G-ABCD',
      aircraftType: 'A320',
      altitudeFt: 950,
      source: 'adsb.lol',
    );
    final Snap snap = _snap(id: 'snap-1', at: at).copyWith(
      status: SnapStatus.confirmed,
      selectedIcao24: 'abc123',
      clipPath: '/data/clip.wav',
      attachClip: true,
      notes: 'Woke the baby.',
      match: FlightMatch(
        candidates: <FlightCandidate>[
          FlightCandidate(
            aircraft: aircraft,
            closestApproachTime: at.subtract(const Duration(seconds: 5)),
            slantRangeM: 340,
            horizontalRangeM: 90,
            heightAboveObserverM: 290,
            elevationDegrees: 72,
            score: 0.9,
            extrapolated: false,
          ),
        ],
        confidence: 0.9,
        searchedFrom: at.subtract(const Duration(seconds: 45)),
        searchedTo: at.add(const Duration(seconds: 10)),
      ),
    );

    await db.upsertSnap(snap);
    final Snap back = (await db.snapById('snap-1'))!;

    // Times go to the database as UTC epoch milliseconds and come back local;
    // the instant must be identical even though the DateTime objects are not.
    expect(back.recordedAt.isAtSameMomentAs(at), isTrue);
    expect(back.latitude, closeTo(51.50012, 1e-9));
    expect(back.metrics.laMaxDb, 78.4);
    expect(back.metrics.calibrated, isFalse);
    expect(back.status, SnapStatus.confirmed);
    expect(back.attachClip, isTrue);
    expect(back.clipPath, '/data/clip.wav');
    expect(back.notes, 'Woke the baby.');
    expect(back.match!.candidates.single.aircraft.callsign, 'BAW123');
    expect(back.confirmedCandidate!.aircraft.registration, 'G-ABCD');
  });

  test('re-saving a snap updates it instead of duplicating it', () async {
    final Snap snap = _snap(id: 'snap-1', at: DateTime(2026, 8, 19, 21));
    await db.upsertSnap(snap);
    await db.upsertSnap(snap.copyWith(status: SnapStatus.sent, notes: 'sent'));

    final List<Snap> all = await db.allSnaps();
    expect(all, hasLength(1));
    expect(all.single.status, SnapStatus.sent);
    expect(all.single.notes, 'sent');
  });

  test('history comes back newest first', () async {
    await db.upsertSnap(_snap(id: 'old', at: DateTime(2026, 8, 19, 9)));
    await db.upsertSnap(_snap(id: 'new', at: DateTime(2026, 8, 19, 21)));
    await db.upsertSnap(_snap(id: 'mid', at: DateTime(2026, 8, 19, 15)));

    expect(
      (await db.allSnaps()).map((Snap s) => s.id).toList(),
      <String>['new', 'mid', 'old'],
    );
  });

  test(
      'only unmatched snaps inside OpenSky\'s one-hour window are '
      'offered for back-fill', () async {
    final DateTime now = DateTime.now();

    // Unmatched and recent: back-fillable.
    await db.upsertSnap(
      _snap(id: 'recent', at: now.subtract(const Duration(minutes: 10))),
    );
    // Unmatched but older than the retrospective window: OpenSky no longer
    // holds it, so asking would burn credits for nothing.
    await db.upsertSnap(
      _snap(id: 'stale', at: now.subtract(const Duration(minutes: 70))),
    );
    // Recent but already dealt with.
    await db.upsertSnap(
      _snap(
        id: 'confirmed',
        at: now.subtract(const Duration(minutes: 5)),
        status: SnapStatus.confirmed,
      ),
    );

    expect(
      (await db.backfillableSnaps()).map((Snap s) => s.id).toList(),
      <String>['recent'],
    );
  });

  test('deleting a snap removes it and leaves the rest alone', () async {
    await db.upsertSnap(_snap(id: 'a', at: DateTime(2026, 8, 19, 9)));
    await db.upsertSnap(_snap(id: 'b', at: DateTime(2026, 8, 19, 10)));

    await db.deleteSnap('a');

    expect(await db.snapById('a'), isNull);
    expect(await db.allSnaps(), hasLength(1));

    // Deleting something that is not there is a no-op, not a crash — the
    // history screen deletes optimistically.
    await db.deleteSnap('a');
  });
}
