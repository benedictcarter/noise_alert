import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBackupChannel(engineBridge.pluginRegistry)
  }

  /// Lets Dart mark the app's data directories as "do not back this up".
  ///
  /// iOS backs up everything in an app's container to iCloud by default, so
  /// without this the complaint database (name, address, and the coordinates of
  /// the user's home against every event) and the microphone recordings are
  /// uploaded to Apple and restored onto the next handset the account touches.
  /// Android says the same thing declaratively in its manifest; on iOS it is a
  /// per-URL attribute and there is no way to set it except from here.
  private func registerBackupChannel(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "NoiseAlertBackup") else { return }

    let channel = FlutterMethodChannel(
      name: "noise_alert/backup",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "excludeFromBackup":
        guard
          let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String]
        else {
          result(
            FlutterError(
              code: "bad_arguments",
              message: "excludeFromBackup expects a list of paths",
              details: nil
            )
          )
          return
        }

        // Each path is attempted independently: one directory that has not
        // been created yet must not stop the others being excluded.
        for path in paths {
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try? url.setResourceValues(values)
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
