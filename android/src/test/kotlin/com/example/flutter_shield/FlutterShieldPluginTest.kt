package com.example.flutter_shield

import android.content.Context
import android.content.pm.ApplicationInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import org.mockito.Mockito.`when`
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class FlutterShieldPluginTest {
    /**
     * Builds a plugin with [FlutterShieldPlugin.onAttachedToEngine] already
     * run against a mocked [FlutterPlugin.FlutterPluginBinding] whose
     * `applicationContext` is a mocked [Context] reporting [debuggable] via
     * its `applicationInfo.flags` — the dependency `checkDebugger`'s
     * dispatch needs that `checkEmulator`'s doesn't.
     */
    private fun attachedPlugin(debuggable: Boolean = false): FlutterShieldPlugin {
        val plugin = FlutterShieldPlugin()
        val messenger: BinaryMessenger = mock(BinaryMessenger::class.java)
        val context: Context = mock(Context::class.java)
        val applicationInfo = ApplicationInfo().apply {
            flags = if (debuggable) ApplicationInfo.FLAG_DEBUGGABLE else 0
        }
        `when`(context.applicationInfo).thenReturn(applicationInfo)
        val binding: FlutterPlugin.FlutterPluginBinding =
            mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
        `when`(binding.applicationContext).thenReturn(context)
        plugin.onAttachedToEngine(binding)
        return plugin
    }

    @Test
    fun onMethodCall_getPlatformVersion_returnsExpectedValue() {
        val plugin = FlutterShieldPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("Android " + android.os.Build.VERSION.RELEASE)
    }

    @Test
    fun onMethodCall_checkEmulator_returnsAnEmulatorDetectionMap() {
        val plugin = FlutterShieldPlugin()
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
    fun onMethodCall_unknownBridgeMethod_returnsNotImplemented() {
        val plugin = FlutterShieldPlugin()
        val call = MethodCall("someFutureSecurityCheck", null)
        val mockResult: MethodChannel.Result = mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(call, mockResult)

        verify(mockResult).notImplemented()
    }

    @Test
    fun sendEvent_withActiveListener_deliversTheCallbackDataShape() {
        val plugin = FlutterShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("onSecurityEvent", "root_detected")

        verify(sink).success(mapOf("callback" to "onSecurityEvent", "data" to "root_detected"))
    }

    @Test
    fun sendEvent_withNullData_forwardsNullDataUnchanged() {
        val plugin = FlutterShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.sendEvent("probe", null)

        verify(sink).success(mapOf("callback" to "probe", "data" to null))
    }

    @Test
    fun sendEvent_withNoActiveListener_isANoOpRatherThanThrowing() {
        val plugin = FlutterShieldPlugin()

        // No listener has ever attached — this must simply not throw.
        plugin.sendEvent("onSecurityEvent", "root_detected")
    }

    @Test
    fun onCancel_stopsRoutingToThePreviousSink() {
        val plugin = FlutterShieldPlugin()
        val sink: EventChannel.EventSink = mock(EventChannel.EventSink::class.java)
        plugin.onListen(null, sink)

        plugin.onCancel(null)
        plugin.sendEvent("probe", "x")

        verifyNoInteractions(sink)
    }

    @Test
    fun onListen_replacesAnyPreviouslyRegisteredSink() {
        val plugin = FlutterShieldPlugin()
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
        val plugin = FlutterShieldPlugin()
        val messenger: BinaryMessenger = mock(BinaryMessenger::class.java)
        val binding: FlutterPlugin.FlutterPluginBinding =
            mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(binding.binaryMessenger).thenReturn(messenger)
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
