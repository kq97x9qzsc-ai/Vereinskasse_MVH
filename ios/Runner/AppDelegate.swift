import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let project = FlutterDartProject()
    let controller = FlutterViewController(project: project, nibName: nil, bundle: nil)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = controller
    // Defer key window until after the current run loop so the implicit engine
    // and platform task runner are further along; mitigates iOS 26 ProMotion
    // crash in createTouchRateCorrectionVSyncClientIfNeeded (null task runner).
    DispatchQueue.main.async {
      DispatchQueue.main.async {
        self.window?.makeKeyAndVisible()
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
