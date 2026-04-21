import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let project = FlutterDartProject()
    let controller = FlutterViewController(project: project, nibName: nil, bundle: nil)
    GeneratedPluginRegistrant.register(with: controller)

    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = controller
    window?.makeKeyAndVisible()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
