import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the app's own data out of the platform's backups.
///
/// The app's promise is that personal data stays on the device. The data is
/// written to app-private directories, which keeps other *apps* out, but says
/// nothing about the operating system: both platforms back an app's private
/// data up to the vendor's cloud by default, and a restore puts the complaint
/// history, the home coordinates in it and the recordings onto whatever handset
/// the account is signed into next. That is personal data leaving the device,
/// by a route no line of this app's code takes.
///
/// Android is handled declaratively in the manifest (`allowBackup="false"` plus
/// `dataExtractionRules`, which covers the device-to-device transfer that
/// `allowBackup` alone does not). iOS has no manifest equivalent: the exclusion
/// is a per-URL file attribute that has to be set from native code, which is
/// what [exclude] reaches through to.
///
/// The trade-off is deliberate and worth stating plainly: a user who replaces
/// their phone loses their complaint history. For a records app that would be
/// the wrong call. For one whose entire pitch is that the evidence never leaves
/// the handset, shipping the evidence to Apple to avoid a migration is worse.
class DeviceBackup {
  const DeviceBackup({MethodChannel channel = _defaultChannel})
      : _channel = channel;

  static const MethodChannel _defaultChannel =
      MethodChannel('noise_alert/backup');

  final MethodChannel _channel;

  /// Marks [paths] as excluded from iCloud and iTunes/Finder backups.
  ///
  /// A no-op everywhere except iOS, and a no-op there too if the channel is
  /// missing. Never throws: failing to exclude is a privacy regression, not a
  /// reason to refuse to start, and the caller has no better answer than
  /// carrying on.
  Future<void> exclude(Iterable<String> paths) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>(
        'excludeFromBackup',
        <String, Object?>{'paths': paths.toList()},
      );
    } on MissingPluginException {
      // An iOS build that predates the native half. Nothing to do.
    } on PlatformException {
      // The file was gone, or the attribute would not set. Either way there is
      // nothing useful to say to a user who is looking at a launch screen.
    }
  }

  /// Excludes the two directories everything the app stores ends up in: the
  /// documents directory (the database) and the support directory (the
  /// recordings, the charts and the evidence maps).
  ///
  /// Directories rather than files, so a clip written after this runs is
  /// covered without anyone having to remember to exclude it too.
  Future<void> excludeAppData() async {
    if (!Platform.isIOS) return;
    await exclude(<String>[
      (await getApplicationDocumentsDirectory()).path,
      (await getApplicationSupportDirectory()).path,
    ]);
  }
}
