package com.geekyants.device_shield.detection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * Exercises MockLocationDetector.evaluate() (the pure decision logic)
 * with synthetic inputs rather than real LocationManager/PackageManager/
 * AppOpsManager/Settings reads — the same constraint RootDetectorTest.kt
 * already documents for its own detector. The velocity computation
 * itself (haversine distance / elapsed time) is private and stateful
 * ([MockLocationDetector.evaluateVelocity]); this test only asserts how
 * `evaluate()` reacts once that boolean is already known, which is the
 * entire surface `evaluate()` is responsible for.
 */
internal class MockLocationDetectorTest {
    private fun cleanDevice(
        permissionGranted: Boolean = true,
        locationAvailable: Boolean = true,
        mockProviderFlag: Boolean = false,
        fakeGpsAppInstalled: Boolean = false,
        mockAppSelectedForThisApp: Boolean = false,
        legacyAllowMockLocationSetting: Boolean = false,
        impossibleVelocity: Boolean = false
    ) = MockLocationDetector.evaluate(
        permissionGranted, locationAvailable, mockProviderFlag, fakeGpsAppInstalled,
        mockAppSelectedForThisApp, legacyAllowMockLocationSetting, impossibleVelocity
    )

    @Test
    fun evaluate_noSignals_reportsNotDetectedWithZeroConfidence() {
        val result = cleanDevice()

        assertEquals(false, result["detected"])
        assertEquals(0.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertTrue((result["signals"] as List<String>).isEmpty())
        assertEquals(true, result["applicable"])
    }

    @Test
    fun evaluate_mockProviderFlagAlone_isDetected() {
        val result = cleanDevice(mockProviderFlag = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("mock_provider_flag"), result["signals"])
        assertEquals(1.0 / 5.0, result["confidence"])
    }

    @Test
    fun evaluate_fakeGpsAppAlone_isDetected() {
        val result = cleanDevice(fakeGpsAppInstalled = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("fake_gps_app_installed"), result["signals"])
    }

    @Test
    fun evaluate_mockAppSelectedForThisAppAlone_isDetected() {
        val result = cleanDevice(mockAppSelectedForThisApp = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("mock_app_selected_for_this_app"), result["signals"])
    }

    @Test
    fun evaluate_legacySettingAlone_isDetected() {
        val result = cleanDevice(legacyAllowMockLocationSetting = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("legacy_allow_mock_location_setting"), result["signals"])
    }

    @Test
    fun evaluate_impossibleVelocityAlone_isDetected() {
        val result = cleanDevice(impossibleVelocity = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("impossible_velocity"), result["signals"])
    }

    @Test
    fun evaluate_everySignalFiring_reportsFullConfidence() {
        val result = MockLocationDetector.evaluate(
            permissionGranted = true,
            locationAvailable = true,
            mockProviderFlag = true,
            fakeGpsAppInstalled = true,
            mockAppSelectedForThisApp = true,
            legacyAllowMockLocationSetting = true,
            impossibleVelocity = true
        )

        assertEquals(true, result["detected"])
        assertEquals(1.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(5, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_partialSignals_reportsProportionalConfidence() {
        val result = cleanDevice(
            mockProviderFlag = true,
            fakeGpsAppInstalled = true
        )

        assertEquals(2.0 / 5.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(2, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_alwaysReportsApplicableTrue() {
        // Unlike RootDetector/JailbreakDetector, mock location is a real
        // concept on both platforms — never a false "not applicable",
        // regardless of permission/location availability.
        val result = cleanDevice(permissionGranted = false, locationAvailable = false)

        assertEquals(true, result["applicable"])
    }

    @Test
    fun evaluate_permissionNotGranted_isCarriedThroughHonestly() {
        val result = cleanDevice(permissionGranted = false, locationAvailable = false)

        assertFalse(result["permissionGranted"] as Boolean)
        assertFalse(result["locationAvailable"] as Boolean)
        // An absent permission is a capability gap, not evidence of a
        // clean device — it must not itself count as, or block, any
        // other signal firing (e.g. a fake GPS app can still be detected
        // with zero location permission at all).
        assertEquals(false, result["detected"])
    }

    @Test
    fun evaluate_permissionNotGranted_stillDetectsPermissionFreeSignals() {
        val result = cleanDevice(
            permissionGranted = false,
            locationAvailable = false,
            fakeGpsAppInstalled = true
        )

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("fake_gps_app_installed"), result["signals"])
    }
}
