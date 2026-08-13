package com.example.flutter_shield

import android.app.Activity
import android.content.Context
import com.example.flutter_shield.detection.DebuggerDetector
import com.example.flutter_shield.detection.EmulatorDetector
import com.example.flutter_shield.detection.RootDetector
import com.example.flutter_shield.detection.ScreenRecordingDetector
import com.example.flutter_shield.detection.ScreenshotDetector
import com.example.flutter_shield.protection.ScreenCaptureProtection
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * FlutterShieldPlugin
 *
 * Phase 7 (Platform Layer / Bridge): registers the two dedicated bridge
 * channels — flutter_shield/native_bridge (MethodChannel) and
 * flutter_shield/events (EventChannel) — alongside the pre-existing
 * flutter_shield channel from Phase 1, kept unchanged for backward
 * compatibility with getPlatformVersion(). "checkEmulator" (M7, FR-03) and
 * "checkDebugger" (M7, FR-04) are the first two real bridge-channel method
 * handlers; every other bridge method still returns notImplemented() until
 * its own detector/protection lands.
 *
 * Adds [sendEvent] — the outbound half of the callback-routing contract
 * `DefaultNativeBridge` already implements on the Dart side (see
 * default_native_bridge.dart): a future detector/protection calls this with
 * its own callback name and payload; this class only shapes and forwards
 * it, with no interpretation of what either means.
 *
 * Screenshot & Screen Recording Protection (see
 * docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md) adds
 * `setScreenshotProtection`/`isScreenCaptureActive` and implements
 * [ActivityAware] — `FLAG_SECURE`
 * ([com.example.flutter_shield.protection.ScreenCaptureProtection]) and the
 * API-34 screenshot callback
 * ([com.example.flutter_shield.detection.ScreenshotDetector]) are both
 * `Activity`/`Window`-level APIs; this plugin previously only held a bare
 * `Context`, which has no `Window`.
 */
class FlutterShieldPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    EventChannel.StreamHandler {
    // Phase 1 legacy channel — untouched, not merged or renamed.
    private lateinit var channel: MethodChannel

    // Phase 7 bridge channels.
    private lateinit var bridgeChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    // M7: DebuggerDetector.check() needs the app's own ApplicationInfo
    // (FLAG_DEBUGGABLE) — captured here, the same lifecycle-bound pattern
    // already used for the three channel fields above.
    private lateinit var applicationContext: Context

    // Screenshot & Screen Recording Protection: null whenever no Activity
    // is currently attached (before onAttachedToActivity, during a
    // configuration-change gap, or after onDetachedFromActivity) — every
    // Activity-dependent call site below checks for null rather than
    // assuming attachment.
    private var activity: Activity? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_shield")
        channel.setMethodCallHandler(this)

        bridgeChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "flutter_shield/native_bridge"
        )
        bridgeChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "flutter_shield/events"
        )
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            "checkEmulator" -> result.success(EmulatorDetector.check())
            "checkDebugger" -> result.success(DebuggerDetector.check(applicationContext))
            "checkRoot" -> result.success(RootDetector.check(applicationContext))
            // "Jailbreak" is not an Android concept — an honest
            // not-applicable answer, never a false "not jailbroken"
            // (design doc: docs/features/ROOT_JAILBREAK_DETECTION.md).
            "checkJailbreak" -> result.success(
                mapOf(
                    "detected" to false,
                    "confidence" to 0.0,
                    "signals" to emptyList<String>(),
                    "applicable" to false,
                )
            )
            "setScreenshotProtection" -> applyFlagSecure(call, result)
            "isScreenCaptureActive" -> result.success(ScreenRecordingDetector.check())
            // On Android this is intentionally the exact same FLAG_SECURE
            // mechanism as setScreenshotProtection above — not a second,
            // independent control. Recents-thumbnail redaction is already
            // a side effect of that one flag (design doc §7.1/§17), so
            // this handler is a documented alias, sharing the same native
            // state, kept as its own method name only for cross-platform
            // API symmetry with iOS (AppSwitcherProtection.swift), where
            // it genuinely is a separate, new mechanism.
            "setAppSwitcherProtection" -> applyFlagSecure(call, result)
            else -> {
                // Bridge transport is registered; most detector/security
                // method handlers don't exist yet — that is out of scope
                // until each one's own milestone lands.
                result.notImplemented()
            }
        }
    }

    /// Shared by `setScreenshotProtection` and `setAppSwitcherProtection`
    /// — both are, on Android, literally the same `FLAG_SECURE` toggle
    /// (see the call-site comment on `setAppSwitcherProtection` above for
    /// why that's intentional, not a bug).
    private fun applyFlagSecure(call: MethodCall, result: Result) {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val currentActivity = activity
        if (currentActivity == null) {
            // No Activity attached yet — nothing to apply the flag to. An
            // honest "not applied" answer, never a silent false success.
            result.success(mapOf("applied" to false))
        } else {
            if (enabled) {
                ScreenCaptureProtection.enable(currentActivity)
            } else {
                ScreenCaptureProtection.disable(currentActivity)
            }
            result.success(mapOf("applied" to true))
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        startObservingScreenshots(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        startObservingScreenshots(binding.activity)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun startObservingScreenshots(currentActivity: Activity) {
        ScreenshotDetector.start(currentActivity) {
            sendEvent(
                "onScreenshotTaken",
                mapOf(
                    "detected" to true,
                    "confidence" to 1.0,
                    "signals" to listOf("screen_capture_callback"),
                ),
            )
        }
    }

    private fun detachActivity() {
        activity?.let { ScreenshotDetector.stop(it) }
        activity = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Sends a native-originated event to Dart, shaped as the
     * `{"callback": callback, "data": data}` payload `DefaultNativeBridge`
     * routes by name on the Dart side. A no-op if nothing is currently
     * listening on the event channel (no subscriber yet, or already torn
     * down) — matches `EventSink`'s own nullability rather than throwing.
     *
     * Transport only: [data]'s content is never inspected here. Must be
     * called on the platform thread — `EventChannel.EventSink` requires it,
     * and this method does no thread-hopping of its own; that is the
     * caller's responsibility once a detector/protection exists to call it.
     */
    internal fun sendEvent(callback: String, data: Any?) {
        eventSink?.success(mapOf("callback" to callback, "data" to data))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        bridgeChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        // Defensive: normal teardown already calls onDetachedFromActivity
        // before this, but this ensures ScreenshotDetector is never left
        // observing a stale Activity if teardown ever happens out of order.
        detachActivity()
    }
}
