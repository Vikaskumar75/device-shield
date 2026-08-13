import Flutter
import UIKit

/// Phase 7 (Platform Layer / Bridge): registers the two dedicated bridge
/// channels — flutter_shield/native_bridge (FlutterMethodChannel) and
/// flutter_shield/events (FlutterEventChannel) — alongside the
/// pre-existing flutter_shield channel from Phase 1, kept unchanged for
/// backward compatibility with getPlatformVersion(). "checkEmulator" (M7,
/// FR-03) and "checkDebugger" (M7, FR-04) are the first two real
/// bridge-channel method handlers; every other bridge method still returns
/// FlutterMethodNotImplemented until its own detector/protection lands.
///
/// Adds `sendEvent` — the outbound half of the callback-routing contract
/// `DefaultNativeBridge` already implements on the Dart side (see
/// default_native_bridge.dart): a future detector/protection calls this
/// with its own callback name and payload; this class only shapes and
/// forwards it, with no interpretation of what either means. Functionally
/// mirrors the Android (`FlutterShieldPlugin.kt`) implementation.
///
/// Screenshot & Screen Recording Protection (see
/// docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md) adds
/// `setScreenshotProtection`/`isScreenCaptureActive` and starts observing
/// for screenshots/capture-state changes at registration time. Unlike
/// Android, this needs no `ActivityAware`-equivalent lifecycle hook —
/// `UIScreen`/`UIApplication`/`NotificationCenter` are all globally
/// available the instant `register(with:)` runs, so observation can begin
/// immediately rather than waiting for any attachment step.
public class FlutterShieldPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  // Phase 7 bridge event sink.
  private var eventSink: FlutterEventSink?

  // Held so onDetachedFromEngine can tear both down, mirroring Android's
  // onDetachedFromEngine cleanup.
  private var bridgeChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FlutterShieldPlugin()

    // Phase 1 legacy channel — untouched, not merged or renamed.
    let channel = FlutterMethodChannel(name: "flutter_shield", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)

    // Phase 7 bridge channels.
    let bridgeChannel = FlutterMethodChannel(
      name: "flutter_shield/native_bridge",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: bridgeChannel)
    instance.bridgeChannel = bridgeChannel

    let eventChannel = FlutterEventChannel(
      name: "flutter_shield/events",
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)
    instance.eventChannel = eventChannel

    instance.startObservingScreenCapture()
    AppSwitcherProtection.start()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "checkEmulator":
      result(EmulatorDetector.check())
    case "checkDebugger":
      result(DebuggerDetector.check())
    case "checkJailbreak":
      result(JailbreakDetector.check())
    case "checkRoot":
      // "Root" is not an iOS concept — an honest not-applicable answer,
      // never a false "not rooted" (design doc:
      // docs/features/ROOT_JAILBREAK_DETECTION.md).
      result([
        "detected": false,
        "confidence": 0.0,
        "signals": [String](),
        "applicable": false,
      ])
    case "setScreenshotProtection":
      // See ScreenCaptureProtection.swift's own top-of-file warning
      // before touching this — NOT a supported Apple API, and its
      // black-screenshot effect is UNCONFIRMED (design doc §18.5: live
      // Simulator testing showed the re-parenting executes but the
      // capture-exclusion did not occur; untested on real hardware).
      // `applied: true` proves only that the re-parenting call executed.
      // An honest "not applied" if there's no root view to protect yet.
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      let applied: Bool
      if enabled {
        if let root = ScreenCaptureProtection.currentRootView() {
          applied = ScreenCaptureProtection.enable(protecting: root)
        } else {
          applied = false
        }
      } else {
        ScreenCaptureProtection.disable()
        applied = true
      }
      result(["applied": applied])
    case "isScreenCaptureActive":
      result(ScreenRecordingDetector.check())
    case "setAppSwitcherProtection":
      // Unlike setScreenshotProtection, this is a real, working mechanism
      // on iOS (AppSwitcherProtection's own doc comment) — the first
      // protection call in this SDK that can honestly report
      // `applied: true` here.
      let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
      let applied = enabled ? AppSwitcherProtection.enable() : AppSwitcherProtection.disable()
      result(["applied": applied])
    default:
      // Bridge transport is registered; most detector/security method
      // handlers don't exist yet — that is out of scope until each one's
      // own milestone lands.
      result(FlutterMethodNotImplemented)
    }
  }

  private func startObservingScreenCapture() {
    ScreenshotDetector.start { [weak self] in
      self?.sendEvent(
        callback: "onScreenshotTaken",
        data: [
          "detected": true,
          "confidence": 1.0,
          "signals": ["screenshot_notification"],
        ]
      )
    }
    ScreenRecordingDetector.start { [weak self] isCaptured in
      self?.sendEvent(
        callback: "onScreenCaptureStateChanged",
        data: ["isCaptured": isCaptured]
      )
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  /// Sends a native-originated event to Dart, shaped as the
  /// `{"callback": callback, "data": data}` payload `DefaultNativeBridge`
  /// routes by name on the Dart side. A no-op if nothing is currently
  /// listening on the event channel (no subscriber yet, or already torn
  /// down) — matches `FlutterEventSink`'s own optionality rather than
  /// throwing.
  ///
  /// Transport only: `data`'s content is never inspected here. Must be
  /// called on the platform (main) thread — `FlutterEventSink` requires it,
  /// and this method does no thread-hopping of its own; that is the
  /// caller's responsibility once a detector/protection exists to call it.
  func sendEvent(callback: String, data: Any?) {
    eventSink?(["callback": callback, "data": data ?? NSNull()])
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    bridgeChannel?.setMethodCallHandler(nil)
    eventChannel?.setStreamHandler(nil)
    eventSink = nil
    ScreenshotDetector.stop()
    ScreenRecordingDetector.stop()
    AppSwitcherProtection.stop()
  }
}
