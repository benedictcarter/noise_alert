import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/profile.dart';
import '../../domain/settings.dart';
import '../../domain/snap.dart';

/// The app's only persistent store, in the app's private directory.
///
/// Nothing here is ever uploaded. The complainant's name, address and postcode
/// live in the `kv` table and leave the device only inside an email the user
/// sends from their own account.
class AppDatabase {
  AppDatabase._(this._db);

  static const int _schemaVersion = 3;
  static const String _kvTable = 'kv';
  static const String _snapTable = 'snaps';

  static const String _keyProfile = 'profile';
  static const String _keySettings = 'settings';

  final Database _db;

  static Future<AppDatabase> open({String? overridePath}) async {
    final String path = overridePath ??
        p.join(
            (await getApplicationDocumentsDirectory()).path, 'noise_alert.db');

    final Database db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_kvTable (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute(_createSnapTable(_snapTable));
        await db.execute(
          'CREATE INDEX idx_snaps_recorded_at ON $_snapTable (recorded_at DESC)',
        );
      },
      onUpgrade: _upgrade,
    );

    return AppDatabase._(db);
  }


  /// v2 made latitude/longitude nullable and added `stale_fix`.
  ///
  /// v1 stored a missing fix as 0, 0 — a real position in the Gulf of Guinea —
  /// so the migration converts exactly those rows back to null. A snap genuinely
  /// taken at Null Island is a loss we can live with.
  static String _createSnapTable(String name) => '''
    CREATE TABLE $name (
      id TEXT PRIMARY KEY,
      recorded_at INTEGER NOT NULL,
      latitude REAL,
      longitude REAL,
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
      notes TEXT NOT NULL DEFAULT '',
      stale_fix INTEGER NOT NULL DEFAULT 0,
      marked_peak_ms INTEGER
    )
  ''';

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      // SQLite cannot drop a NOT NULL constraint in place, so the table is
      // rebuilt. Done inside the migration transaction sqflite already holds.
      await db.execute(_createSnapTable('${_snapTable}_v2'));
      await db.execute('''
        INSERT INTO ${_snapTable}_v2 (
          id, recorded_at, latitude, longitude, gps_accuracy_m, gps_altitude_m,
          metrics_json, status, clip_path, attach_clip, match_json,
          selected_icao24, unidentified, sent_at, device_model, os_version,
          app_version, notes, stale_fix
        )
        SELECT
          id, recorded_at,
          CASE WHEN latitude = 0 AND longitude = 0 THEN NULL ELSE latitude END,
          CASE WHEN latitude = 0 AND longitude = 0 THEN NULL ELSE longitude END,
          gps_accuracy_m, gps_altitude_m, metrics_json, status, clip_path,
          attach_clip, match_json, selected_icao24, unidentified, sent_at,
          device_model, os_version, app_version, notes, 0
        FROM $_snapTable
      ''');
      await db.execute('DROP TABLE $_snapTable');
      await db.execute('ALTER TABLE ${_snapTable}_v2 RENAME TO $_snapTable');
      await db.execute(
        'CREATE INDEX idx_snaps_recorded_at ON $_snapTable (recorded_at DESC)',
      );
    }
    if (from >= 2 && to >= 3) {
      // Only for tables the v2 branch above did not just build from the current
      // schema, which already has the column.
      await db.execute(
        'ALTER TABLE $_snapTable ADD COLUMN marked_peak_ms INTEGER',
      );
    }
  }

  Future<void> close() => _db.close();

  // --- key/value -------------------------------------------------------

  Future<Map<String, Object?>?> _readJson(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _kvTable,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value']! as String) as Map<String, Object?>;
  }

  Future<void> _writeJson(String key, Map<String, Object?> value) async {
    await _db.insert(
      _kvTable,
      <String, Object?>{'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ComplainantProfile> loadProfile() async {
    final Map<String, Object?>? json = await _readJson(_keyProfile);
    return json == null
        ? const ComplainantProfile()
        : ComplainantProfile.fromJson(json);
  }

  Future<void> saveProfile(ComplainantProfile profile) =>
      _writeJson(_keyProfile, profile.toJson());

  Future<AppSettings> loadSettings() async {
    final Map<String, Object?>? json = await _readJson(_keySettings);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  Future<void> saveSettings(AppSettings settings) =>
      _writeJson(_keySettings, settings.toJson());

  // --- snaps -----------------------------------------------------------

  Future<void> upsertSnap(Snap snap) async {
    await _db.insert(
      _snapTable,
      snap.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Snap>> allSnaps({int limit = 500}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _snapTable,
      orderBy: 'recorded_at DESC',
      limit: limit,
    );
    return rows.map(Snap.fromRow).toList();
  }

  Future<Snap?> snapById(String id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      _snapTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Snap.fromRow(rows.first);
  }

  /// Snaps that never got a flight match and are still inside OpenSky's
  /// one-hour retrospective window.
  Future<List<Snap>> backfillableSnaps() async {
    final int cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 55))
        .millisecondsSinceEpoch;
    final List<Map<String, Object?>> rows = await _db.query(
      _snapTable,
      // A snap with no position can never be matched, however often it is
      // retried, so it is not offered for back-fill.
      where: 'status = ? AND recorded_at > ? AND latitude IS NOT NULL',
      whereArgs: <Object?>[SnapStatus.unmatched.name, cutoff],
      orderBy: 'recorded_at ASC',
    );
    return rows.map(Snap.fromRow).toList();
  }

  Future<void> deleteSnap(String id) async {
    await _db.delete(_snapTable, where: 'id = ?', whereArgs: <Object?>[id]);
  }
}
