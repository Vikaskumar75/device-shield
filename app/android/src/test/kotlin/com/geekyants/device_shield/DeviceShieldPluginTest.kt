package com.geekyants.device_shield

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.view.Window
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.mockito.Mockito.`when`

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class DeviceShieldPluginTest {
    /**
     * Builds a plugin with [DeviceShieldPlugin.onAttachedToEngine] already
     * run against a mocked [FlutterPlugin.FlutterPluginBinding] whose
     * `applicationContext` is a mocked [Context] reporting [debuggable] via
     * its `applicationInfo.flags` — the dependency `checkDebugger`'s
     * dispatch needs that `checkEmulator`'s doesn't. Also stubs
     * `context.packageManager` to throw `NameNotFoundException` for every
     * package lookup — the realistic "nothing installed" default
     * `RootDetector.anyPackageInstalled` needs, since an unstubbed
     * Mockito mock otherwise returns `null` for `packageManager` itself,
     * not a `PackageManager` that throws per-lookup.
     */
    private fun attachedPlugin(debuggable: Boolean = false): DeviceShieldPlugin {
        val plugin = DeviceShieldPlugin()
        val messenger: BinaryMessenger = mock(BinaryMessenger::class.java)
        val context: Context = mock(Context::class.java)
        val applicationInfo = ApplicationInfo().apply {
            flags = if (debuggable) ApplicationInfo.FLAG_DEBUGGABLE else 0
        }
        `when`(context.applicationInfo).thenReturn(applicationInfo)
        val packageManager: PackageManager = mock(PackageManager::class.java)
        `when`(packageManager.getPackageInfo(Mockito.anyString(), Mockito.anyInt()))
            .thenThrow(PackageManager.NameNotFoundException())
        `when`(context.packageManager).thenReturn(packageManager)
        val binding: FlutterPlugin.FlutterPluginBinding =
            mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
        `when`(binding.applicationContext).thenReturn(context)
        plugin.onAttachedToEngine(binding)
        return plugin
    }

    @Test
    fun onMethodCall_getPlatformVersion_returnsExpectedValue() {
        val plugin = DeviceShieldPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("Android " + android.os.Build.VERSION.RELEASE)
    }

    @Test
    fun onMethodCall_checkEmulator_returnsAnEmulatorDetectionMap() {
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("checkEmulator", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertTrue(response.containsKey("detected"))
        assertTrue(response.containsKey("confidence"))
        assertTrue(response.containsKey("signals"))
    }

    @Test
    fun onMethodCall_checkDebugger_returnsADebuggerDetectionMap() {
        val plugin = attachedPlugin(debuggable = false)
        val call = MethodCall("checkDebugger", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertTrue(response.containsKey("detected"))
        assertTrue(response.containsKey("confidence"))
        assertTrue(response.containsKey("signals"))
    }

    @Test
    fun onMethodCall_checkDebugger_reflectsTheApplicationsDebuggableFlag() {
        // android.os.Debug.isDebuggerConnected()/waitingForDebugger() are
        // forced to their Kotlin/Java default (false) by this module's
        // isReturnDefaultValues test option (see build.gradle.kts) — the
        // one signal this test can deterministically control end-to-end
        // through the real plugin dispatch path is the debuggable-build
        // flag, via the mocked Context this test supplies.
        val plugin = attachedPlugin(debuggable = true)
        val call = MethodCall("checkDebugger", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertEquals(true, response["detected"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(listOf("debuggable_flag"), response["signals"] as List<String>)
    }

    @Test
    fun onMethodCall_checkRoot_returnsARootDetectionMap() {
        val plugin = attachedPlugin(debuggable = false)
        val call = MethodCall("checkRoot", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertTrue(response.containsKey("detected"))
        assertTrue(response.containsKey("confidence"))
        assertTrue(response.containsKey("signals"))
        assertEquals(true, response["applicable"])
    }

    @Test
    fun onMethodCall_checkJailbreak_returnsTheHonestNotApplicableMap() {
        // "Jailbreak" is not an Android concept — never a false "not
        // jailbroken".
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("checkJailbreak", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertEquals(false, response["detected"])
        assertEquals(0.0, response["confidence"])
        assertEquals(false, response["applicable"])
    }

    @Test
    fun onMethodCall_checkMockLocation_returnsAMockLocationDetectionMap() {
        val plugin = attachedPlugin(debuggable = false)
        val call = MethodCall("checkMockLocation", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        val response = captor.value
        assertTrue(response.containsKey("detected"))
        assertTrue(response.containsKey("confidence"))
        assertTrue(response.containsKey("signals"))
        assertTrue(response.containsKey("permissionGranted"))
        assertTrue(response.containsKey("locationAvailable"))
        // Unlike checkJailbreak on Android, mock location is a real
        // concept on both platforms — never a false "not applicable".
        assertEquals(true, response["applicable"])
    }

    /** A mocked [ActivityPluginBinding] whose `activity` has a mocked
     * [Window], for Screenshot & Screen Recording Protection's
     * Activity-dependent calls. */
    private fun activityBinding(): Triple<ActivityPluginBinding, Activity, Window> {
        val window: Window = mock(Window::class.java)
        val activity: Activity = mock(Activity::class.java)
        `when`(activity.window).thenReturn(window)
        val binding: ActivityPluginBinding = mock(ActivityPluginBinding::class.java)
        `when`(binding.activity).thenReturn(activity)
        return Triple(binding, activity, window)
    }

    @Test
    fun onMethodCall_setScreenshotProtection_withNoActivityAttached_reportsNotApplied() {
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun onMethodCall_setScreenshotProtection_enabled_setsFlagSecureAndReportsApplied() {
        val plugin = DeviceShieldPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        verify(mockResult).success(mapOf("applied" to true))
    }

    @Test
    fun onMethodCall_setScreenshotProtection_disabled_clearsFlagSecureAndReportsApplied() {
        val plugin = DeviceShieldPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to false))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        verify(mockResult).success(mapOf("applied" to true))
    }

    @Test
    fun onMethodCall_setScreenshotProtection_afterActivityDetached_reportsNotApplied() {
        val plugin = DeviceShieldPlugin()
        val (binding, _, _) = activityBinding()
        plugin.onAttachedToActivity(binding)
        plugin.onDetachedFromActivity()
        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun onMethodCall_setAppSwitcherProtection_withNoActivityAttached_reportsNotApplied() {
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("setAppSwitcherProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun onMethodCall_setAppSwitcherProtection_enabled_setsTheSameFlagSecureAsScreenshotProtection() {
        // Documented alias on Android — see DeviceShieldPlugin.kt's own
        // comment on the setAppSwitcherProtection case: this is
        // intentionally the identical FLAG_SECURE mechanism, not a second
        // one, because Recents redaction is already that flag's side
        // effect (design doc §7.1/§18.1).
        val plugin = DeviceShieldPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val call = MethodCall("setAppSwitcherProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        verify(mockResult).success(mapOf("applied" to true))
    }

    @Test
    fun onMethodCall_setAppSwitcherProtection_disabled_clearsFlagSecureAndReportsApplied() {
        val plugin = DeviceShieldPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val call = MethodCall("setAppSwitcherProtection", mapOf("enabled" to false))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        verify(mockResult).success(mapOf("applied" to true))
    }

    @Test
    fun onMethodCall_isScreenCaptureActive_returnsTheHonestUnsupportedMap() {
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("isScreenCaptureActive", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        val captor = org.mockito.ArgumentCaptor.forClass(Map::class.java)
        verify(mockResult).success(captor.capture())
        assertEquals(false, captor.value["supported"])
        assertEquals(false, captor.value["isCaptured"])
    }

    @Test
    fun onDetachedFromEngine_alsoClearsAnyAttachedActivity() {
        // Defensive cleanup — see DeviceShieldPlugin's own doc comment on
        // onDetachedFromEngine. Verified indirectly: setScreenshotProtection
        // reports not-applied after full engine detach, exactly as it
        // would after onDetachedFromActivity alone.
        val plugin = DeviceShieldPlugin()
        val messenger: BinaryMessenger = mock(BinaryMessenger::class.java)
        val engineBinding: FlutterPlugin.FlutterPluginBinding =
            mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(engineBinding.binaryMessenger).thenReturn(messenger)
        `when`(engineBinding.applicationContext).thenReturn(mock(Context::class.java))
        plugin.onAttachedToEngine(engineBinding)
        val (activityBinding, _, _) = activityBinding()
        plugin.onAttachedToActivity(activityBinding)

        plugin.onDetachedFromEngine(engineBinding)

        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)
        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun onMethodCall_unknownBridgeMethod_returnsNotImplemented() {
        val plugin = DeviceShieldPlugin()
        val call = MethodCall("someFutureSecurityCheck", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).notImplemented()
    }

    @Test
    fun sendEvent_withActiveListener_deliversTheCallbackDataShape() {
        val plugin = DeviceShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("onSecurityEvent", "root_detected")

        verify(sink).success(mapOf("callback" to "onSecurityEvent", "data" to "root_detected"))
    }

    @Test
    fun sendEvent_withNullData_forwardsNullDataUnchanged() {
        val plugin = DeviceShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("probe", null)

        verify(sink).success(mapOf("callback" to "probe", "data" to null))
    }

    @Test
    fun sendEvent_withNoActiveListener_isANoOpRatherThanThrowing() {
        val plugin = DeviceShieldPlugin()

        // No listener has ever attached — this must simply not throw.
        plugin.sendEvent("onSecurityEvent", "root_detected")
    }

    @Test
    fun onCancel_stopsRoutingToThePreviousSink() {
        val plugin = DeviceShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.onCancel(null)
        plugin.sendEvent("probe", "x")

        verifyNoInteractions(sink)
    }

    @Test
    fun onListen_replacesAnyPreviouslyRegisteredSink() {
        val plugin = DeviceShieldPlugin()
        val firstSink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        val secondSink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, firstSink)

        plugin.onListen(null, secondSink)
        plugin.sendEvent("probe", "x")

        verifyNoInteractions(firstSink)
        verify(secondSink).success(mapOf("callback" to "probe", "data" to "x"))
    }

    @Test
    fun onDetachedFromEngine_removesBothChannelHandlersAndClearsTheEventSink() {
        val plugin = DeviceShieldPlugin()
        val messenger: BinaryMessenger = mock(BinaryMessenger::class.java)
        val binding: FlutterPlugin.FlutterPluginBinding =
            mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
        `when`(binding.applicationContext).thenReturn(mock(Context::class.java))
        plugin.onAttachedToEngine(binding)
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.onDetachedFromEngine(binding)

        // All three channel handlers are unregistered from the messenger:
        // the legacy channel, the bridge MethodChannel, and the bridge
        // EventChannel (setStreamHandler(null) is itself a
        // setMessageHandler(name, null) call — see EventChannel.java).
        verify(messenger, Mockito.times(3))
            .setMessageHandler(Mockito.anyString(), Mockito.isNull())
        // The event sink is cleared as part of the same cleanup — a
        // sendEvent call after detach is dropped, not routed to the stale
        // sink.
        plugin.sendEvent("probe", "x")
        verify(sink, never()).success(Mockito.any())
    }
}
