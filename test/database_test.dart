import 'dart:convert';
import 'dart:io';

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
  preRollSeconds: 30,
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

test('a marked worst moment survives the round trip and can be cleared',
      () async {
    final Snap snap = _snap(id: 'marked', at: DateTime(2026, 8, 19, 21))
        .copyWith(markedPeakMs: 42500);
    await db.upsertSnap(snap);

    expect((await db.snapById('marked'))!.markedPeakMs, 42500);

    // Clearing has to survive too: copyWith cannot express "back to null"
    // through the value alone, which is exactly the bug clearMarkedPeak exists
    // to prevent.
    await db.upsertSnap(snap.copyWith(clearMarkedPeak: true));
    expect((await db.snapById('marked'))!.markedPeakMs, isNull);
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

  test('a snap with no fix round trips as null, not as zero', () async {
    // 0, 0 is a real place. Storing it for "unknown" would put a coordinate in
    // the Gulf of Guinea into a complaint letter and centre the flight search
    // there, which is worse than admitting the fix is missing.
    final Snap unlocated = Snap(
      id: 'no-fix',
      recordedAt: DateTime(2026, 8, 19, 12),
      metrics: _metrics,
      status: SnapStatus.unmatched,
      deviceModel: 'LG G7 ThinQ',
      osVersion: 'Android 10 (SDK 29)',
      appVersion: '0.1.0+1',
    );

    await db.upsertSnap(unlocated);
    final Snap? read = await db.snapById('no-fix');

    expect(read, isNotNull);
    expect(read!.latitude, isNull);
    expect(read.longitude, isNull);
    expect(read.hasLocation, isFalse);
  });

  test('a cached last-known fix is marked stale across the round trip',
      () async {
    await db.upsertSnap(
      Snap(
        id: 'stale-fix',
        recordedAt: DateTime(2026, 8, 19, 12),
        latitude: 51.5,
        longitude: -0.1,
        staleFix: true,
        metrics: _metrics,
        status: SnapStatus.unmatched,
      ),
    );

    expect((await db.snapById('stale-fix'))!.staleFix, isTrue);
  });

  test('back-fill skips snaps with no location', () async {
    // There is nothing to ask OpenSky: the query is a radius around a point we
    // do not have. Left in, it would burn the rate limit on every poll forever.
    final DateTime now = DateTime.now();
    await db.upsertSnap(_snap(id: 'located', at: now));
    await db.upsertSnap(
      Snap(
        id: 'unlocated',
        recordedAt: now,
        metrics: _metrics,
        status: SnapStatus.unmatched,
      ),
    );

    expect(
      (await db.backfillableSnaps()).map((Snap s) => s.id).toList(),
      <String>['located'],
    );
  });

  group('v1 to v2 migration', () {
    // A real file, not inMemoryDatabasePath: an in-memory database is destroyed
    // when it is closed, so there would be nothing left to re-open and upgrade.
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('noise_alert_migration');
      path = '${dir.path}/noise_alert.db';
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> seedV1(double lat, double lon) async {
      final Database v1 = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int _) async {
          await db.execute(
            'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          // The v1 shape verbatim: NOT NULL coordinates, no stale_fix column.
          await db.execute(_v1SnapsTable);
        },
      );
      await v1.insert('snaps', <String, Object?>{
        'id': 'legacy',
        'recorded_at': DateTime(2026, 8, 18, 11).millisecondsSinceEpoch,
        'latitude': lat,
        'longitude': lon,
        'metrics_json': jsonEncode(_metrics.toJson()),
        'status': 'unmatched',
      });
      await v1.close();
    }

    test('a 0, 0 row becomes a genuinely absent fix', () async {
      await seedV1(0, 0);

      final AppDatabase upgraded = await AppDatabase.open(overridePath: path);
      addTearDown(upgraded.close);
      final Snap? snap = await upgraded.snapById('legacy');

      expect(snap, isNotNull);
      expect(snap!.latitude, isNull);
      expect(snap.longitude, isNull);
      expect(snap.hasLocation, isFalse);
      // Everything else must survive: these are the user's own records.
      expect(snap.metrics.laMaxDb, 78.4);
      expect(snap.status, SnapStatus.unmatched);
    });

    test('a v1 database gains the marked-peak column on the way to v3',
        () async {
      // The column was added by an ALTER on top of the v2 rebuild, so the
      // 1 -> 3 path is the one that can go wrong: a chain that only ever runs
      // one hop in testing will happily skip a step in the field.
      await seedV1(51.50012, -0.10034);

      final AppDatabase upgraded = await AppDatabase.open(overridePath: path);
      addTearDown(upgraded.close);

      final Snap legacy = (await upgraded.snapById('legacy'))!;
      expect(legacy.markedPeakMs, isNull);

      await upgraded.upsertSnap(legacy.copyWith(markedPeakMs: 7000));
      expect((await upgraded.snapById('legacy'))!.markedPeakMs, 7000);
    });

    test('a real fix is carried through untouched', () async {
      await seedV1(51.50012, -0.10034);

      final AppDatabase upgraded = await AppDatabase.open(overridePath: path);
      addTearDown(upgraded.close);
      final Snap snap = (await upgraded.snapById('legacy'))!;

      expect(snap.latitude, closeTo(51.50012, 1e-9));
      expect(snap.longitude, closeTo(-0.10034, 1e-9));
      expect(snap.staleFix, isFalse);
    });
  });

  group('the Flightpath Watch group CC', () {
    test('a fresh install copies the group by default', () {
      const AppSettings fresh = AppSettings();

      expect(
        fresh.activeRecipientSet.cc,
        contains(RecipientSet.flightpathWatchCc),
      );
    });

    test('settings saved before the group address existed pick it up', () {
      // No recipientSeed key at all: written by a build that predates the
      // group mailbox. Such a record must gain the CC exactly once.
      final Map<String, Object?> old = <String, Object?>{
        'recipientSets': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'default',
            'label': 'Default',
            'to': <String>['me@example.com'],
            'cc': <String>[],
          },
        ],
      };

      final AppSettings seeded = AppSettings.fromJson(old);

      expect(
        seeded.activeRecipientSet.cc,
        <String>[RecipientSet.flightpathWatchCc],
      );
      expect(seeded.recipientSeed, AppSettings.currentRecipientSeed);
      expect(seeded.activeRecipientSet.to, <String>['me@example.com']);
    });

    test('a user who deleted the group CC does not get it back', () {
      // The seeding pass is why this test exists: a default that reapplies
      // itself on every load is not a default, it is a policy, and the
      // recipient list is the user's.
      const AppSettings settings = AppSettings(
        recipientSets: <RecipientSet>[
          RecipientSet(
            id: 'default',
            label: 'Default',
            to: <String>['me@example.com'],
          ),
        ],
      );

      final AppSettings back = AppSettings.fromJson(settings.toJson());

      expect(back.activeRecipientSet.cc, isEmpty);
    });

    test('a set the user made themselves is left alone', () {
      const RecipientSet mine = RecipientSet(
        id: 'heathrow',
        label: 'Heathrow',
        to: <String>['noise@example.com'],
      );

      expect(RecipientSet.seedGroupCc(mine), mine);
    });
  });
}

const String _v1SnapsTable = '''
  CREATE TABLE snaps (
    id TEXT PRIMARY KEY,
    recorded_at INTEGER NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    gps_accuracy_m REAL,
    gps_altitude_m REAL,
    metrics_json TEXT NOT NULL,
    status TEXT NOT NULL,
    clip_path TEXT,
    attach_clip INTEGER NOT NULL DEFAULT 0,
    match_json TEXT,
    selected_icao24 TEXT,
    unidentified INTEGER NOT NULL DEFAULT 0,
    sent_at INTEGER,
    device_model TEXT NOT NULL DEFAULT '',
    os_version TEXT NOT NULL DEFAULT '',
    app_version TEXT NOT NULL DEFAULT '',
    notes TEXT NOT NULL DEFAULT ''
  )
''';
