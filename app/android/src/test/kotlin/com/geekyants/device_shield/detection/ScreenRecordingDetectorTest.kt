package com.example.flutter_shield.detection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * ScreenRecordingDetector is a pure, stateless "always unsupported on
 * Android" responder (design doc §7.1/§9.5, and Step 5's own Architecture
 * Verification Report) — no real OS call to separate from pure logic here,
 * unlike EmulatorDetector/DebuggerDetector.
 */
internal class ScreenRecordingDetectorTest {
    @Test
    fun check_alwaysReportsUnsupported() {
        val result = ScreenRecordingDetector.check()

        assertEquals(false, result["supported"])
    }

    @Test
    fun check_neverFabricatesADetectedCaptureState() {
        val result = ScreenRecordingDetector.check()

        // Never a false, confident "recording" claim either — isCaptured
        // must always be false alongside supported:false, per the design
        // doc's "never a false, confident answer" rule (§13).
        assertFalse(result["isCaptured"] as Boolean)
    }

    @Test
    fun check_includesAHumanReadableReason() {
        val result = ScreenRecordingDetector.check()

        assertTrue((result["reason"] as String).isNotBlank())
    }
}
