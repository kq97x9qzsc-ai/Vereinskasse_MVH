import Flutter
import ObjectiveC

/// Workaround for https://github.com/flutter/flutter/issues/183900 (iOS 26 + ProMotion + implicit engine):
/// `-[FlutterViewController createTouchRateCorrectionVSyncClientIfNeeded]` can run with a nil
/// `platformTaskRunner` and crash inside `-[VSyncClient initWithTaskRunner:callback:]`.
/// Official fix: https://github.com/flutter/flutter/pull/184639 — remove this file's `install()` call once shipped.
enum FlutterVSyncTouchRateWorkaround {
  static func install() {
    let sel = NSSelectorFromString("createTouchRateCorrectionVSyncClientIfNeeded")
    guard let cls = NSClassFromString("FlutterViewController") as? AnyClass,
          let method = class_getInstanceMethod(cls, sel) else { return }
    typealias Block = @convention(block) (AnyObject) -> Void
    let block: Block = { _ in }
    let imp = imp_implementationWithBlock(block)
    method_setImplementation(method, imp)
  }
}
