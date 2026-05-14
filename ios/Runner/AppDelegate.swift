import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Exclude DB + secure-storage from iCloud backup (Plan C-2 hardening).
    if let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let dbPath = docs.appendingPathComponent("dreambook.db")
        if FileManager.default.fileExists(atPath: dbPath.path) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = dbPath
            try? url.setResourceValues(values)
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
