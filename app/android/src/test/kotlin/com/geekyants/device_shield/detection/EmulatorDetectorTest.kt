package com.geekyants.device_shield.detection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * Exercises EmulatorDetector.evaluate() (the pure decision logic) with
 * synthetic inputs rather than real android.os.Build.* values, which are
 * static and effectively unmockable in a plain JVM unit test without
 * Robolectric.
 */
internal class EmulatorDetectorTest {
    private fun realDevice(
        fingerprint: String = "samsung/beyond2ltexx/beyond2:14/UP1A.231005.007/G975FXXSGHWK1:user/release-keys",
        model: String = "SM-G975F",
        manufacturer: String = "samsung",
        hardware: String = "exynos9820",
        product: String = "beyond2ltexx",
        brand: String = "samsung",
        device: String = "beyond2",
        anyQemuPipeExists: Boolean = false
    ) = EmulatorDetector.evaluate(
        fingerprint,
        model,
        manufacturer,
        hardware,
        product,
        brand,
        device,
        anyQemuPipeExists
    )

    @Test
    fun evaluate_realDeviceSignature_reportsNotDetectedWithZeroConfidence() {
        val result = realDevice()

        assertEquals(false, result["detected"])
        assertEquals(0.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertTrue((result["signals"] as List<String>).isEmpty())
    }

    @Test
    fun evaluate_genericFingerprint_isDetectedWithPartialConfidence() {
        val result = realDevice(fingerprint = "generic/sdk/generic:14/x/y:userdebug/test-keys")

        assertEquals(true, result["detected"])
        @Suppress("UNCHECKED_CAST")
        val signals = result["signals"] as List<String>
        assertTrue(signals.contains("fingerprint"))
        assertEquals(1, signals.size)
        assertEquals(1.0 / 7.0, result["confidence"])
    }

    @Test
    fun evaluate_everySignalFiring_reportsFullConfidence() {
        val result = EmulatorDetector.evaluate(
            fingerprint = "generic/google_sdk/generic",
            model = "Android SDK built for x86",
            manufacturer = "Genymotion",
            hardware = "goldfish",
            product = "sdk_gphone_x86",
            brand = "generic",
            device = "generic_x86",
            anyQemuPipeExists = true
        )

        assertEquals(true, result["detected"])
        assertEquals(1.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(7, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_qemuPipeAlone_isDetected() {
        val result = realDevice(anyQemuPipeExists = true)

        assertTrue(result["detected"] as Boolean)
        @Suppress("UNCHECKED_CAST")
        assertEquals(listOf("qemu_pipe"), result["signals"])
    }

    @Test
    fun evaluate_genericBrandRequiresBothBrandAndDeviceToMatch() {
        val brandOnly = realDevice(brand = "generic", device = "beyond2")
        assertFalse(brandOnly["detected"] as Boolean)

        val both = realDevice(brand = "generic", device = "generic_x86")
        assertTrue(both["detected"] as Boolean)
    }
}
