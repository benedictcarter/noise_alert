import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Make, model and OS version of the handset.
///
/// This goes in every complaint. There is no calibration certificate behind a
/// phone microphone, so telling the recipient exactly what recorded the number
/// is the honest substitute: it lets them weigh it, and it lets a future
/// per-device calibration table be applied retrospectively.
class DeviceDescription {
  const DeviceDescription({
    required this.model,
    required this.osVersion,
    required this.appVersion,
  });

  final String model;
  final String osVersion;
  final String appVersion;

  static const DeviceDescription unknown = DeviceDescription(
    model: 'unknown device',
    osVersion: 'unknown OS',
    appVersion: '',
  );

}

class DeviceInfoService {
  DeviceInfoService();

  DeviceDescription? _cached;

  Future<DeviceDescription> describe() async {
    final DeviceDescription? cached = _cached;
    if (cached != null) return cached;

    String model = 'unknown device';
    String osVersion = 'unknown OS';

    final DeviceInfoPlugin plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo info = await plugin.androidInfo;
      model = '${info.manufacturer} ${info.model}'.trim();
      osVersion =
          'Android ${info.version.release} (SDK ${info.version.sdkInt})';
    } else if (Platform.isIOS) {
      final IosDeviceInfo info = await plugin.iosInfo;
      model =
          info.utsname.machine.isNotEmpty ? info.utsname.machine : info.model;
      osVersion = '${info.systemName} ${info.systemVersion}';
    }

    String appVersion = '';
    try {
      final PackageInfo package = await PackageInfo.fromPlatform();
      appVersion = '${package.version}+${package.buildNumber}';
    } on Object {
      // Version string is cosmetic; never let it block a capture.
    }

    final DeviceDescription description = DeviceDescription(
      model: model,
      osVersion: osVersion,
      appVersion: appVersion,
    );
    _cached = description;
    return description;
  }
}
