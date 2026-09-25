package com.geekyants.device_shield.detection

import android.os.Build
import java.io.File

/**
 * FR-03 (SRS section 5.3): heuristic emulator detection via well-known
 * Build-fingerprint/hardware signals. Every signal is independently weak
 * evidence; confidence is proportional to how many fire at once. Real
 * hardware may still occasionally match one signal (e.g. a customized
 * ROM) — that is expected heuristic behavior, not a bug: this reports a
 * confidence score, never a certainty claim.
 */
object EmulatorDetector {
    private val KNOWN_QEMU_PIPES = listOf("/dev/socket/qemud", "/dev/qemu_pipe")
    private const val SIGNAL_CATEGORY_COUNT = 7.0

    fun check(): Map<String, Any> {
        // Build's fields are Java platform types (nullable from Kotlin's
        // perspective) even though real devices always populate them —
        // coerced to "" defensively so a field this code doesn't control
        // being unexpectedly null degrades to "no signal from that
        // field," never a crash.
        return evaluate(
            fingerprint = Build.FINGERPRINT ?: "",
            model = Build.MODEL ?: "",
            manufacturer = Build.MANUFACTURER ?: "",
            hardware = Build.HARDWARE ?: "",
            product = Build.PRODUCT ?: "",
            brand = Build.BRAND ?: "",
            device = Build.DEVICE ?: "",
            anyQemuPipeExists = KNOWN_QEMU_PIPES.any { File(it).exists() }
        )
    }

    /**
     * Pure decision logic, separated from the Build fields and
     * file-system reads in [check] above so it can be unit-tested with
     * synthetic inputs — Build's fields are static and effectively
     * unmockable in a plain JVM unit test without Robolectric, which this
     * project doesn't use.
     */
    internal fun evaluate(
        fingerprint: String,
        model: String,
        manufacturer: String,
        hardware: String,
        product: String,
        brand: String,
        device: String,
        anyQemuPipeExists: Boolean
    ): Map<String, Any> {
        val signals = mutableListOf<String>()

        if (fingerprint.startsWith("generic") || fingerprint.startsWith("unknown")) {
            signals.add("fingerprint")
        }
        if (model.contains("google_sdk") ||
            model.contains("Emulator") ||
            model.contains("Android SDK built for")
        ) {
            signals.add("model")
        }
        if (manufacturer.contains("Genymotion")) {
            signals.add("manufacturer")
        }
        if (hardware.contains("goldfish") ||
            hardware.contains("ranchu") ||
            hardware.contains("vbox")
        ) {
            signals.add("hardware")
        }
        if (product.contains("sdk") ||
            product.contains("vbox86p") ||
            product.contains("emulator")
        ) {
            signals.add("product")
        }
        if (brand.startsWith("generic") && device.startsWith("generic")) {
            signals.add("brand_device")
        }
        if (anyQemuPipeExists) {
            signals.add("qemu_pipe")
        }

        val confidence = (signals.size / SIGNAL_CATEGORY_COUNT).coerceAtMost(1.0)
        return mapOf(
            "detected" to signals.isNotEmpty(),
            "confidence" to confidence,
            "signals" to signals
        )
    }
}
