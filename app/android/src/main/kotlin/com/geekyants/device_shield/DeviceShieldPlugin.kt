package com.geekyants.device_shield

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.geekyants.device_shield.detection.DebuggerDetector
import com.geekyants.device_shield.detection.EmulatorDetector
import com.geekyants.device_shield.detection.MockLocationDetector
import com.geekyants.device_shield.detection.RootDetector
import com.geekyants.device_shield.detection.ScreenRecordingDetector
import com.geekyants.device_shield.detection.ScreenshotDetector
import com.geekyants.device_shield.protection.ScreenCaptureProtection
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * DeviceShieldPlugin
 *
 * Phase 7 (Platform Layer / Bridge): registers the two dedicated bridge
 * channels — device_shield/native_bridge (MethodChannel) and
 * device_shield/events (EventChannel) — alongside the pre-existing
 * device_shield channel from Phase 1, kept unchanged for backward
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
 * ([com.geekyants.device_shield.protection.ScreenCaptureProtection]) and the
 * API-34 screenshot callback
 * ([com.geekyants.device_shield.detection.ScreenshotDetector]) are both
 * `Activity`/`Window`-level APIs; this plugin previously only held a bare
 * `Context`, which has no `Window`.
 */
class DeviceShieldPlugin internal constructor(
    // Where detection work runs, and where its results are delivered. Tests
    // pass executors that run immediately; production uses [CHECK_EXECUTOR]
    // and the main looper.
    private val background: Executor,
    private val mainThread: Executor
) : FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    EventChannel.StreamHandler {
    // Phase 1 legacy channel — untouched, not merged or renamed.
    // Flutter's generated plugin registrant needs a no-argument constructor.
    constructor() : this(CHECK_EXECUTOR, MAIN_THREAD)

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

    private var screenshotProtection = false
    private var appSwitcherProtection = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "device_shield")
        channel.setMethodCallHandler(this)

        bridgeChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "device_shield/native_bridge"
        )
        bridgeChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "device_shield/events"
        )
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")

            "checkEmulator" -> respondInBackground(result) { EmulatorDetector.check() }

            "checkDebugger" -> respondInBackground(result) { DebuggerDetector.check(applicationContext) }

            "checkRoot" -> respondInBackground(result) { RootDetector.check(applicationContext) }

            // "Jailbreak" is not an Android concept — an honest
            // not-applicable answer, never a false "not jailbroken"
            // (design doc: docs/features/ROOT_JAILBREAK_DETECTION.md).
            "checkJailbreak" -> result.success(
                mapOf(
                    "detected" to false,
                    "confidence" to 0.0,
                    "signals" to emptyList<String>(),
                    "applicable" to false
                )
            )

            // FR-06: real signal evaluation on both platforms — mock
            // location is a real concept on Android and iOS alike, unlike
            // checkRoot/checkJailbreak's platform-exclusive concepts.
            "checkMockLocation" -> respondInBackground(result) { MockLocationDetector.check(applicationContext) }

            "setScreenshotProtection" -> setProtection(call, result) { screenshotProtection = it }

            "isScreenCaptureActive" -> result.success(ScreenRecordingDetector.check())

            // FLAG_SECURE also hides the Recents thumbnail, so on Android both
            // protections are the same flag. Each keeps its own state, and the
            // flag stays set while either is on.
            "setAppSwitcherProtection" -> setProtection(call, result) { appSwitcherProtection = it }

            else -> {
                // Bridge transport is registered; most detector/security
                // method handlers don't exist yet — that is out of scope
                // until each one's own milestone lands.
                result.notImplemented()
            }
        }
    }

    /**
     * Runs [check] off the platform main thread and replies on it. Root and
     * mock-location checks start processes and query `PackageManager`, which
     * would otherwise block the UI.
     *
     * Everything is caught: an exception escaping a background thread would
     * crash the host app, where on the main thread Flutter turned it into a
     * channel error. Dart reports that error as `CheckStatus.failed`.
     */
    @Suppress("TooGenericExceptionCaught")
    private fun respondInBackground(result: Result, check: () -> Any?) {
        background.execute {
            try {
                val value = check()
                mainThread.execute { result.success(value) }
            } catch (error: Exception) {
                mainThread.execute { result.error("CHECK_FAILED", error.message, null) }
            }
        }
    }

    private fun setProtection(call: MethodCall, result: Result, update: (Boolean) -> Unit) {
        val currentActivity = activity
        if (currentActivity == null) {
            // No window to apply the flag to yet; Dart reports this as failed.
            result.success(mapOf("applied" to false))
            return
        }
        update(call.argument<Boolean>("enabled") ?: false)
        applyFlagSecure(currentActivity)
        result.success(mapOf("applied" to true))
    }

    private fun applyFlagSecure(currentActivity: Activity) {
        if (screenshotProtection || appSwitcherProtection) {
            ScreenCaptureProtection.enable(currentActivity)
        } else {
            ScreenCaptureProtection.disable(currentActivity)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding.activity)
    }

    private fun attachActivity(currentActivity: Activity) {
        activity = currentActivity
        startObservingScreenshots(currentActivity)
        // A configuration change (e.g. rotation) creates a new window without
        // FLAG_SECURE. Re-apply protection that was on. Only when on, so a
        // flag the host app set itself is left alone.
        if (screenshotProtection || appSwitcherProtection) {
            ScreenCaptureProtection.enable(currentActivity)
        }
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
                    "signals" to listOf("screen_capture_callback")
                )
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

    private companion object {
        /**
         * One thread for the whole process, so checks run one at a time:
         * `MockLocationDetector` keeps the previous fix in memory. It's a
         * daemon thread, so it never keeps the process alive.
         */
        val CHECK_EXECUTOR: Executor by lazy {
            Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "device_shield-checks").apply { isDaemon = true }
            }
        }

        // Lazy, so JVM unit tests that inject their own executors never touch
        // the (unmocked) Android main looper.
        val MAIN_THREAD: Executor by lazy {
            val handler = Handler(Looper.getMainLooper())
            Executor { command -> handler.post(command) }
        }
    }
}
