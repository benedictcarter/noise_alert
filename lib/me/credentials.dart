import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:noise_alert/me/settings.dart';

/// The one secret the app holds: the user's OpenSky client secret.
///
/// It lives in the platform keystore rather than in the settings row, because
/// the settings row is JSON in SQLite and SQLite is a file like any other. A
/// file in the app's data directory is private to the app, but it is not
/// private to a *backup* of the app, and until this existed the secret went
/// wherever the backup went. The keystore is the one place on either platform
/// that a restore onto a different handset cannot carry.
///
/// The client *id* is deliberately left in settings. It is an account
/// identifier, not a credential: it cannot authenticate on its own, and keeping
/// it in the settings row means the Recordings screen can still show at a
/// glance whether credentials are configured without unlocking anything.
///
/// Every method degrades to "no secret" rather than throwing. A handset with a
/// broken keystore, or a unit test with no platform channel at all, must still
/// get an app that runs: the only thing lost is the OpenSky back-fill, which is
/// optional by design.
class CredentialStore {
  /// Android needs no options. The plugin's default is already AES-GCM under a
  /// key wrapped by the Android KeyStore, which is what is wanted here; the
  /// `encryptedSharedPreferences` flag is deprecated, off by default and gone
  /// in the next major, so passing anything would only pin us to the mode being
  /// removed. iOS does need options, and that is the whole reason to be careful.
  CredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                // The default keychain accessibility is *not* device-only, and
                // a keychain item that is not device-only is itself carried in
                // an iCloud backup. Leaving this at the default would put the
                // secret straight back into the place this class exists to
                // keep it out of, having moved it out of the database to get
                // it there.
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _openSkySecretKey = 'opensky_client_secret';

  Future<String> readOpenSkySecret() async {
    try {
      return await _storage.read(key: _openSkySecretKey) ?? '';
    } on MissingPluginException {
      return '';
    } on PlatformException {
      return '';
    }
  }

  /// Writes, or clears the entry outright when [secret] is empty.
  ///
  /// Clearing has to delete rather than store an empty string, so that a user
  /// who removes their credentials leaves nothing behind to read back.
  Future<void> writeOpenSkySecret(String secret) async {
    try {
      if (secret.isEmpty) {
        await _storage.delete(key: _openSkySecretKey);
      } else {
        await _storage.write(key: _openSkySecretKey, value: secret);
      }
    } on MissingPluginException {
      // No keystore here (tests, desktop). Nothing is persisted, which is the
      // safe direction to fail in.
    } on PlatformException {
      // Same, for a keystore that exists but refuses.
    }
  }
}

/// Puts the OpenSky secret back onto [stored], and gets it out of the database
/// if this is the first run since it stopped being kept there.
///
/// The migration is the whole point of the function. Moving new writes to the
/// keystore would leave every existing install with its secret still sitting in
/// the settings row, which is the copy that backups and file-level access
/// actually reach, so finding one there means: write it to the keystore, then
/// save the settings straight back. [AppSettings.toJson] no longer emits the
/// key, so that save is what scrubs it, and it happens exactly once because the
/// next load finds nothing to migrate.
///
/// [resave] is passed in rather than a database, so that this stays a decision
/// about credentials and not a second place that knows how settings are stored.
Future<AppSettings> restoreOpenSkySecret({
  required AppSettings stored,
  required CredentialStore credentials,
  required Future<void> Function(AppSettings scrubbed) resave,
}) async {
  if (stored.openSkyClientSecret.isNotEmpty) {
    await credentials.writeOpenSkySecret(stored.openSkyClientSecret);
    await resave(stored);
    return stored;
  }
  return stored.copyWith(
    openSkyClientSecret: await credentials.readOpenSkySecret(),
  );
}
