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
import java.util.concurrent.Executor
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
    /** Runs work immediately, so tests can assert results synchronously. */
    private val immediate = Executor { it.run() }

    /** An executor that only queues work, so a test controls when it runs. */
    private class QueuedExecutor : Executor {
        val pending = ArrayDeque<Runnable>()

        override fun execute(command: Runnable) {
            pending.addLast(command)
        }

        fun runAll() {
            while (pending.isNotEmpty()) pending.removeFirst().run()
        }
    }

    private fun newPlugin(background: Executor = immediate, mainThread: Executor = immediate) =
        DeviceShieldPlugin(background, mainThread)

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
    private fun attachedPlugin(
        debuggable: Boolean = false,
        background: Executor = immediate,
        mainThread: Executor = immediate
    ): DeviceShieldPlugin {
        val plugin = newPlugin(background, mainThread)
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
        val plugin = newPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("Android " + android.os.Build.VERSION.RELEASE)
    }

    @Test
    fun onMethodCall_checkEmulator_returnsAnEmulatorDetectionMap() {
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
        val call = MethodCall("setScreenshotProtection", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun onMethodCall_setScreenshotProtection_enabled_setsFlagSecureAndReportsApplied() {
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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
        val plugin = newPlugin()
        val call = MethodCall("someFutureSecurityCheck", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).notImplemented()
    }

    @Test
    fun sendEvent_withActiveListener_deliversTheCallbackDataShape() {
        val plugin = newPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("onSecurityEvent", "root_detected")

        verify(sink).success(mapOf("callback" to "onSecurityEvent", "data" to "root_detected"))
    }

    @Test
    fun sendEvent_withNullData_forwardsNullDataUnchanged() {
        val plugin = newPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("probe", null)

        verify(sink).success(mapOf("callback" to "probe", "data" to null))
    }

    @Test
    fun sendEvent_withNoActiveListener_isANoOpRatherThanThrowing() {
        val plugin = newPlugin()

        // No listener has ever attached — this must simply not throw.
        plugin.sendEvent("onSecurityEvent", "root_detected")
    }

    @Test
    fun onCancel_stopsRoutingToThePreviousSink() {
        val plugin = newPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.onCancel(null)
        plugin.sendEvent("probe", "x")

        verifyNoInteractions(sink)
    }

    @Test
    fun onListen_replacesAnyPreviouslyRegisteredSink() {
        val plugin = newPlugin()
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
        val plugin = newPlugin()
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

    @Test
    fun detectionRunsOnTheBackgroundExecutorAndRepliesOnTheMainThread() {
        val background = QueuedExecutor()
        val mainThread = QueuedExecutor()
        val plugin = attachedPlugin(background = background, mainThread = mainThread)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("checkRoot", null), mockResult)

        // Nothing runs on the calling (main) thread.
        assertEquals(1, background.pending.size)
        verifyNoInteractions(mockResult)

        background.runAll()
        // The check ran, but the reply waits for the main thread.
        assertEquals(1, mainThread.pending.size)
        verifyNoInteractions(mockResult)

        mainThread.runAll()
        verify(mockResult).success(Mockito.any())
    }

    @Test
    fun aCheckThatThrowsRepliesWithAnErrorInsteadOfCrashing() {
        // Without onAttachedToEngine, applicationContext is uninitialised, so
        // the root check throws inside the background task.
        val plugin = newPlugin()
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("checkRoot", null), mockResult)

        verify(mockResult).error(Mockito.eq("CHECK_FAILED"), Mockito.any(), Mockito.isNull())
        verify(mockResult, never()).success(Mockito.any())
    }

    @Test
    fun protectionStaysOnTheCallingThread() {
        val background = QueuedExecutor()
        val plugin = newPlugin(background = background)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("setScreenshotProtection", mapOf("enabled" to true)), mockResult)

        assertTrue(background.pending.isEmpty())
        verify(mockResult).success(mapOf("applied" to false))
    }

    @Test
    fun disablingOneProtectionKeepsFlagSecureWhileTheOtherIsOn() {
        val plugin = newPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val result: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("setScreenshotProtection", mapOf("enabled" to true)), result)
        plugin.onMethodCall(MethodCall("setAppSwitcherProtection", mapOf("enabled" to false)), result)

        verify(window, never()).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    @Test
    fun flagSecureIsClearedOnlyWhenBothProtectionsAreOff() {
        val plugin = newPlugin()
        val (binding, _, window) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val result: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("setScreenshotProtection", mapOf("enabled" to true)), result)
        plugin.onMethodCall(MethodCall("setAppSwitcherProtection", mapOf("enabled" to true)), result)
        plugin.onMethodCall(MethodCall("setScreenshotProtection", mapOf("enabled" to false)), result)
        verify(window, never()).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)

        plugin.onMethodCall(MethodCall("setAppSwitcherProtection", mapOf("enabled" to false)), result)
        verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    @Test
    fun protectionIsReappliedToTheNewWindowAfterAConfigurationChange() {
        val plugin = newPlugin()
        val (binding, _, _) = activityBinding()
        plugin.onAttachedToActivity(binding)
        val result: MethodChannel.Result = mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall("setScreenshotProtection", mapOf("enabled" to true)), result)

        plugin.onDetachedFromActivityForConfigChanges()
        val (newBinding, _, newWindow) = activityBinding()
        plugin.onReattachedToActivityForConfigChanges(newBinding)

        verify(newWindow).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    @Test
    fun attachingWithoutProtectionLeavesTheWindowFlagsAlone() {
        val plugin = newPlugin()
        val (binding, _, window) = activityBinding()

        plugin.onAttachedToActivity(binding)

        verify(window, never()).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        verify(window, never()).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
