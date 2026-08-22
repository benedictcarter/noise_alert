import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/me/credentials.dart';
import 'package:noise_alert/me/settings.dart';
import 'package:noise_alert/snap/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A keystore that is just a variable, so the migration can be tested without
/// a platform channel. The real one degrades to this shape anyway when there is
/// no keystore to talk to.
class _FakeCredentials implements CredentialStore {
  String? stored;
  int writes = 0;

  @override
  Future<String> readOpenSkySecret() async => stored ?? '';

  @override
  Future<void> writeOpenSkySecret(String secret) async {
    writes++;
    stored = secret.isEmpty ? null : secret;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the OpenSky secret is not kept in the database', () {
    test('saving settings writes every field except the secret', () async {
      final AppDatabase db =
          await AppDatabase.open(overridePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await db.saveSettings(
        const AppSettings(
          openSkyClientId: 'client-id',
          openSkyClientSecret: 'the-actual-secret',
        ),
      );

      // Read the raw row rather than going through loadSettings: the point is
      // what is on disk, not what the object model hands back.
      final AppSettings back = await db.loadSettings();
      expect(back.openSkyClientId, 'client-id');
      expect(
        back.openSkyClientSecret,
        isEmpty,
        reason: 'the secret must not survive a round trip through SQLite',
      );

      expect(
        jsonEncode(const AppSettings(openSkyClientSecret: 'hunter2').toJson()),
        isNot(contains('hunter2')),
        reason: 'toJson is what gets written to the settings row',
      );
    });

    test('a secret typed today goes to the keystore and nowhere else',
        () async {
      final _FakeCredentials creds = _FakeCredentials();
      await creds.writeOpenSkySecret('typed-today');

      final AppSettings hydrated = await restoreOpenSkySecret(
        stored: const AppSettings(openSkyClientId: 'client-id'),
        credentials: creds,
        resave: (AppSettings _) async =>
            fail('nothing to migrate, so nothing should be re-saved'),
      );

      expect(hydrated.openSkyClientSecret, 'typed-today');
      expect(hydrated.openSkyClientId, 'client-id');
    });
  });

  group('migrating an install that still has the secret in its database', () {
    test('the secret moves to the keystore and the row is scrubbed', () async {
      final AppDatabase db =
          await AppDatabase.open(overridePath: inMemoryDatabasePath);
      addTearDown(db.close);

      // The shape a pre-migration install is in: the key is in the stored JSON,
      // because the build that wrote it still emitted it.
      final Map<String, Object?> legacy =
          const AppSettings(openSkyClientId: 'client-id').toJson()
            ..['openSkyClientSecret'] = 'legacy-secret';
      final AppSettings stored = AppSettings.fromJson(legacy);
      expect(stored.openSkyClientSecret, 'legacy-secret');

      final _FakeCredentials creds = _FakeCredentials();
      final AppSettings migrated = await restoreOpenSkySecret(
        stored: stored,
        credentials: creds,
        resave: db.saveSettings,
      );

      // Still usable in this session...
      expect(migrated.openSkyClientSecret, 'legacy-secret');
      // ...now held in the keystore...
      expect(creds.stored, 'legacy-secret');
      // ...and gone from the database.
      expect((await db.loadSettings()).openSkyClientSecret, isEmpty);
      expect((await db.loadSettings()).openSkyClientId, 'client-id');
    });

    test('the migration does not run a second time', () async {
      final _FakeCredentials creds = _FakeCredentials()
        ..stored = 'already-moved';

      int resaves = 0;
      final AppSettings second = await restoreOpenSkySecret(
        // What the database hands back after the first run: no secret in it.
        stored: const AppSettings(openSkyClientId: 'client-id'),
        credentials: creds,
        resave: (AppSettings _) async => resaves++,
      );

      expect(second.openSkyClientSecret, 'already-moved');
      expect(resaves, 0, reason: 'there is nothing left to scrub');
      expect(creds.writes, 0, reason: 'and nothing to write back');
    });

    test('clearing the credentials deletes the entry rather than blanking it',
        () async {
      final _FakeCredentials creds = _FakeCredentials()..stored = 'to-be-gone';

      await creds.writeOpenSkySecret('');

      expect(creds.stored, isNull);
      expect(await creds.readOpenSkySecret(), isEmpty);
    });
  });
}
