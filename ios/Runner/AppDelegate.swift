import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  lazy var flutterEngine = FlutterEngine(name: "vereinskasse_engine")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)

    let controller = FlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = controller
    window?.makeKeyAndVisible()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
