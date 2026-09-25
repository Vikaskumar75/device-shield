package com.geekyants.device_shield.detection

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/**
 * FR-01 (SRS section 5.1): heuristic root detection via nine independent
 * signal categories. Every signal is individually weak evidence (a false
 * positive or false negative on any single category is expected, normal
 * heuristic behavior — see docs/features/ROOT_JAILBREAK_DETECTION.md);
 * confidence is proportional to how many fire at once, the same
 * signal-count model [EmulatorDetector]/[DebuggerDetector] already use.
 *
 * Two categories are documented, deliberately, as weaker than the rest
 * rather than silently included as if equally authoritative:
 * - [systemWritable]: systemless Magisk (the dominant rooting method
 *   since ~2019, OverlayFS/magic-mount) frequently leaves `/system`
 *   genuinely read-only — false negatives on this signal are expected on
 *   the most common current rooting method, not a bug.
 * - [buildTagsTestKeys]: legitimate custom ROMs (LineageOS, GrapheneOS)
 *   and some OEM engineering/retail builds ship `test-keys` without
 *   being rooted — a real false-positive source on this signal alone.
 */
object RootDetector {
    private val SU_PATHS = listOf(
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "/su/bin/su",
        "/system/sd/xbin/su",
        "/system/bin/failsafe/su",
        "/data/local/xbin/su",
        "/data/local/bin/su",
        "/data/local/su"
    )

    private val MAGISK_PATHS = listOf(
        "/sbin/.magisk",
        "/cache/.magisk",
        "/data/adb/magisk",
        "/data/adb/modules"
    )

    private val BUSYBOX_PATHS = listOf(
        "/system/xbin/busybox",
        "/system/bin/busybox"
    )

    // Known root-manager app packages — separate from ROOT_CLOAKING_PACKAGES
    // below since installing a root manager and installing a tool whose
    // whole purpose is *hiding* root from apps like this one are distinct,
    // independently meaningful signals.
    private val SUPERUSER_PACKAGES = listOf(
        "com.topjohnwu.magisk",
        "eu.chainfire.supersu",
        "com.noshufou.android.su",
        "com.noshufou.android.su.elite",
        "com.koushikdutta.superuser",
        "com.thirdparty.superuser",
        "com.yellowes.su",
        "com.kingroot.kinguser",
        "com.kingo.root",
        "com.smedialink.oneclickroot",
        "com.zhiqupk.root.global",
        "me.phh.superuser",
        "com.ramdroid.appquarantine"
    )

    private val ROOT_CLOAKING_PACKAGES = listOf(
        "com.amphoras.hidemyroot",
        "com.amphoras.hidemyrootadfree",
        "com.formyhm.hideroot",
        "com.formyhm.hiderootpremium",
        "com.zachspong.temprootremovejb",
        "com.devadvance.rootcloak",
        "com.devadvance.rootcloakplus",
        "com.saurik.substrate"
    )

    private const val SIGNAL_CATEGORY_COUNT = 9.0

    fun check(context: Context): Map<String, Any> = evaluate(
        suBinaryPathExists = SU_PATHS.any { File(it).exists() },
        suExecutableOnPath = isExecutableOnPath("su"),
        superuserAppInstalled = anyPackageInstalled(context, SUPERUSER_PACKAGES),
        magiskArtifactsExist = MAGISK_PATHS.any { File(it).exists() },
        systemWritable = isPathWritable("/system") || isPathWritable("/system/bin"),
        busyBoxExists = BUSYBOX_PATHS.any { File(it).exists() },
        buildTagsTestKeys = (Build.TAGS ?: "").contains("test-keys"),
        dangerousPropsSet = isDangerousPropSet(),
        rootCloakingAppInstalled = anyPackageInstalled(context, ROOT_CLOAKING_PACKAGES)
    )

    /**
     * Pure decision logic, separated from the real filesystem/process/
     * PackageManager/Build reads in [check] above so it can be
     * unit-tested with synthetic inputs — the same constraint
     * [EmulatorDetector]/[DebuggerDetector] already document for their
     * own `Build.*`/`Debug.*` reads.
     */
    internal fun evaluate(
        suBinaryPathExists: Boolean,
        suExecutableOnPath: Boolean,
        superuserAppInstalled: Boolean,
        magiskArtifactsExist: Boolean,
        systemWritable: Boolean,
        busyBoxExists: Boolean,
        buildTagsTestKeys: Boolean,
        dangerousPropsSet: Boolean,
        rootCloakingAppInstalled: Boolean
    ): Map<String, Any> {
        val signals = mutableListOf<String>()

        if (suBinaryPathExists) signals.add("su_binary_path")
        if (suExecutableOnPath) signals.add("su_executable")
        if (superuserAppInstalled) signals.add("superuser_apps_installed")
        if (magiskArtifactsExist) signals.add("magisk_artifacts")
        if (systemWritable) signals.add("writable_system")
        if (busyBoxExists) signals.add("busybox_present")
        if (buildTagsTestKeys) signals.add("build_tags_test_keys")
        if (dangerousPropsSet) signals.add("dangerous_system_props")
        if (rootCloakingAppInstalled) signals.add("root_cloaking_apps_installed")

        val confidence = (signals.size / SIGNAL_CATEGORY_COUNT).coerceAtMost(1.0)
        return mapOf(
            "detected" to signals.isNotEmpty(),
            "confidence" to confidence,
            "signals" to signals,
            "applicable" to true
        )
    }

    /**
     * Requires `<queries><package android:name="..."/></queries>` entries
     * in this plugin's own AndroidManifest.xml — since Android 11 (API
     * 30), `getPackageInfo()` for a specific undeclared package throws
     * [PackageManager.NameNotFoundException] regardless of whether it's
     * actually installed, unless declared via `<queries>` or the
     * `QUERY_ALL_PACKAGES` permission (deliberately not used — heavy Play
     * Console scrutiny for a generic security SDK to force on every host
     * app). `<queries>` merges into the host app's manifest automatically
     * via Gradle, with no host-app config required.
     */
    private fun anyPackageInstalled(context: Context, packages: List<String>): Boolean {
        val packageManager = context.packageManager
        return packages.any { packageName ->
            try {
                packageManager.getPackageInfo(packageName, 0)
                true
            } catch (ignored: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    /**
     * `File.canWrite()` alone is unreliable for `/system` on modern
     * Android (SELinux policy frequently reports a misleading answer) —
     * an actual write-and-delete attempt is the standard, more honest
     * technique. Still an inherently weak signal for the reason this
     * class's own doc comment states.
     */
    private fun isPathWritable(path: String): Boolean {
        val testFile = File(path, ".device_shield_root_check")
        return try {
            val created = testFile.createNewFile()
            if (created) testFile.delete()
            created
        } catch (ignored: Exception) {
            false
        }
    }

    /**
     * Shells out to the `getprop` binary rather than reflecting into the
     * hidden `android.os.SystemProperties` class — that class is on
     * Android's non-SDK interface restriction list on modern API levels,
     * and reflecting into it risks a `NoSuchMethodException`/policy
     * concern this plain process call has none of.
     */
    private fun isDangerousPropSet(): Boolean {
        val debuggable = runShellCommand("getprop", "ro.debuggable")
        val secure = runShellCommand("getprop", "ro.secure")
        return debuggable == "1" || secure == "0"
    }

    private fun isExecutableOnPath(binary: String): Boolean {
        val result = runShellCommand("which", binary)
        return !result.isNullOrEmpty()
    }

    private fun runShellCommand(vararg command: String): String? = try {
        val process = ProcessBuilder(*command).redirectErrorStream(true).start()
        val output = BufferedReader(InputStreamReader(process.inputStream))
            .readLine()
            ?.trim()
        process.waitFor()
        output
    } catch (ignored: Exception) {
        null
    }
}
