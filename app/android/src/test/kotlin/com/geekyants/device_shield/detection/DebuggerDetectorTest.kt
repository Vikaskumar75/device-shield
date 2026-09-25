package com.geekyants.device_shield.detection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * Exercises DebuggerDetector.evaluate() (the pure decision logic) with
 * synthetic inputs rather than real android.os.Debug.* / Context calls,
 * which throw in a plain JVM unit test without Robolectric — the same
 * constraint EmulatorDetectorTest.kt already documents for android.os.Build.
 */
internal class DebuggerDetectorTest {
    @Test
    fun evaluate_noSignals_reportsNotDetectedWithZeroConfidence() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = false,
            waitingForDebugger = false,
            debuggableFlag = false
        )

        assertEquals(false, result["detected"])
        assertEquals(0.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertTrue((result["signals"] as List<String>).isEmpty())
    }

    @Test
    fun evaluate_debuggerConnectedAlone_isDetectedWithPartialConfidence() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = true,
            waitingForDebugger = false,
            debuggableFlag = false
        )

        assertEquals(true, result["detected"])
        @Suppress("UNCHECKED_CAST")
        val signals = result["signals"] as List<String>
        assertEquals(listOf("debugger_connected"), signals)
        assertEquals(1.0 / 3.0, result["confidence"])
    }

    @Test
    fun evaluate_waitingForDebuggerAlone_isDetected() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = false,
            waitingForDebugger = true,
            debuggableFlag = false
        )

        assertTrue(result["detected"] as Boolean)
        @Suppress("UNCHECKED_CAST")
        assertEquals(listOf("waiting_for_debugger"), result["signals"])
    }

    @Test
    fun evaluate_debuggableFlagAlone_isDetectedWithWeakestSignal() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = false,
            waitingForDebugger = false,
            debuggableFlag = true
        )

        assertTrue(result["detected"] as Boolean)
        @Suppress("UNCHECKED_CAST")
        assertEquals(listOf("debuggable_flag"), result["signals"])
    }

    @Test
    fun evaluate_everySignalFiring_reportsFullConfidence() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = true,
            waitingForDebugger = true,
            debuggableFlag = true
        )

        assertEquals(true, result["detected"])
        assertEquals(1.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(3, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_twoOfThreeSignals_reportsProportionalConfidence() {
        val result = DebuggerDetector.evaluate(
            debuggerConnected = true,
            waitingForDebugger = true,
            debuggableFlag = false
        )

        assertFalse((result["signals"] as List<*>).contains("debuggable_flag"))
        assertEquals(2.0 / 3.0, result["confidence"])
    }
}
