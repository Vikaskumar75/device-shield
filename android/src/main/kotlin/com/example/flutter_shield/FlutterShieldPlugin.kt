package com.example.flutter_shield

import android.content.Context
import com.example.flutter_shield.detection.DebuggerDetector
import com.example.flutter_shield.detection.EmulatorDetector
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
 */
class FlutterShieldPlugin :
    FlutterPlugin,
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
            else -> {
                // Bridge transport is registered; most detector/security
                // method handlers don't exist yet — that is out of scope
                // until each one's own milestone lands.
                result.notImplemented()
            }
        }
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
    }
}
