package com.example.flutter_shield.detection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * Exercises RootDetector.evaluate() (the pure decision logic) with
 * synthetic inputs rather than real filesystem/PackageManager/Build
 * reads, which either require a real device or are static/unmockable in
 * a plain JVM unit test without Robolectric — the same constraint
 * EmulatorDetectorTest.kt already documents.
 */
internal class RootDetectorTest {
    private fun nonRootedDevice(
        suBinaryPathExists: Boolean = false,
        suExecutableOnPath: Boolean = false,
        superuserAppInstalled: Boolean = false,
        magiskArtifactsExist: Boolean = false,
        systemWritable: Boolean = false,
        busyBoxExists: Boolean = false,
        buildTagsTestKeys: Boolean = false,
        dangerousPropsSet: Boolean = false,
        rootCloakingAppInstalled: Boolean = false
    ) = RootDetector.evaluate(
        suBinaryPathExists, suExecutableOnPath, superuserAppInstalled,
        magiskArtifactsExist, systemWritable, busyBoxExists, buildTagsTestKeys,
        dangerousPropsSet, rootCloakingAppInstalled
    )

    @Test
    fun evaluate_noSignals_reportsNotDetectedWithZeroConfidence() {
        val result = nonRootedDevice()

        assertEquals(false, result["detected"])
        assertEquals(0.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertTrue((result["signals"] as List<String>).isEmpty())
        assertEquals(true, result["applicable"])
    }

    @Test
    fun evaluate_suBinaryPathAlone_isDetected() {
        val result = nonRootedDevice(suBinaryPathExists = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("su_binary_path"), result["signals"])
        assertEquals(1.0 / 9.0, result["confidence"])
    }

    @Test
    fun evaluate_suExecutableAlone_isDetected() {
        val result = nonRootedDevice(suExecutableOnPath = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("su_executable"), result["signals"])
    }

    @Test
    fun evaluate_superuserAppAlone_isDetected() {
        val result = nonRootedDevice(superuserAppInstalled = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("superuser_apps_installed"), result["signals"])
    }

    @Test
    fun evaluate_magiskArtifactsAlone_isDetected() {
        val result = nonRootedDevice(magiskArtifactsExist = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("magisk_artifacts"), result["signals"])
    }

    @Test
    fun evaluate_writableSystemAlone_isDetected() {
        val result = nonRootedDevice(systemWritable = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("writable_system"), result["signals"])
    }

    @Test
    fun evaluate_busyBoxAlone_isDetected() {
        val result = nonRootedDevice(busyBoxExists = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("busybox_present"), result["signals"])
    }

    @Test
    fun evaluate_buildTagsTestKeysAlone_isDetected() {
        val result = nonRootedDevice(buildTagsTestKeys = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("build_tags_test_keys"), result["signals"])
    }

    @Test
    fun evaluate_dangerousPropsAlone_isDetected() {
        val result = nonRootedDevice(dangerousPropsSet = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("dangerous_system_props"), result["signals"])
    }

    @Test
    fun evaluate_rootCloakingAppAlone_isDetected() {
        val result = nonRootedDevice(rootCloakingAppInstalled = true)

        assertTrue(result["detected"] as Boolean)
        assertEquals(listOf("root_cloaking_apps_installed"), result["signals"])
    }

    @Test
    fun evaluate_everySignalFiring_reportsFullConfidence() {
        val result = RootDetector.evaluate(
            suBinaryPathExists = true,
            suExecutableOnPath = true,
            superuserAppInstalled = true,
            magiskArtifactsExist = true,
            systemWritable = true,
            busyBoxExists = true,
            buildTagsTestKeys = true,
            dangerousPropsSet = true,
            rootCloakingAppInstalled = true
        )

        assertEquals(true, result["detected"])
        assertEquals(1.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(9, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_partialSignals_reportsProportionalConfidence() {
        val result = nonRootedDevice(
            suBinaryPathExists = true,
            magiskArtifactsExist = true,
            busyBoxExists = true
        )

        assertEquals(3.0 / 9.0, result["confidence"])
        @Suppress("UNCHECKED_CAST")
        assertEquals(3, (result["signals"] as List<String>).size)
    }

    @Test
    fun evaluate_alwaysReportsApplicableTrue() {
        // Unlike JailbreakDetector on Android, RootDetector always
        // applies on Android — never a false "not applicable".
        val result = nonRootedDevice()

        assertEquals(true, result["applicable"])
    }
}
