import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:noise_alert/app.dart';
import 'package:noise_alert/snap/database.dart';
import 'package:noise_alert/me/credentials.dart';
import 'package:noise_alert/me/device_backup.dart';
import 'package:noise_alert/me/profile.dart';
import 'package:noise_alert/me/settings.dart';
import 'package:noise_alert/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything is read or written: tell iOS not to back any of it up.
  // Android says the same thing in its manifest, where it applies from install
  // rather than from first launch. Awaited because it is quick and because the
  // one moment it must not miss is the first run on a fresh install, when the
  // directories are made and the first recording lands seconds later.
  await const DeviceBackup().excludeAppData();

  // Opened before the first frame so every screen can read settings and the
  // profile synchronously: the alternative is a loading spinner over the one
  // button the whole app exists to show.
  final AppDatabase database = await AppDatabase.open();
  final ComplainantProfile profile = await database.loadProfile();

  // The stored settings come back without the OpenSky secret, which lives in
  // the keystore. On an install that predates that, this is also what moves it
  // there and scrubs the copy in the database.
  final AppSettings settings = await restoreOpenSkySecret(
    stored: await database.loadSettings(),
    credentials: CredentialStore(),
    resave: database.saveSettings,
  );

  runApp(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(database),
        initialSettingsProvider.overrideWithValue(settings),
        initialProfileProvider.overrideWithValue(profile),
      ],
      child: const NoiseAlertApp(),
    ),
  );
}
