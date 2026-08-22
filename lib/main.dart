import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:noise_alert/app.dart';
import 'package:noise_alert/snap/database.dart';
import 'package:noise_alert/me/profile.dart';
import 'package:noise_alert/me/settings.dart';
import 'package:noise_alert/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before the first frame so every screen can read settings and the
  // profile synchronously: the alternative is a loading spinner over the one
  // button the whole app exists to show.
  final AppDatabase database = await AppDatabase.open();
  final AppSettings settings = await database.loadSettings();
  final ComplainantProfile profile = await database.loadProfile();

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
