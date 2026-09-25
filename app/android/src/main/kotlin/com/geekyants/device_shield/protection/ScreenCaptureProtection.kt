package com.geekyants.device_shield.protection

import android.app.Activity
import android.view.WindowManager

/**
 * Screenshot & Screen Recording Protection —
 * doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §7.1/§9.5.
 *
 * `FLAG_SECURE` set/clear — a single `Window` flag that blocks *both*
 * screenshots and screen recording/mirroring of this activity's content
 * simultaneously (one native mechanism, not two — design doc §4.1/§7.1),
 * and hides this app's content from the Recent Apps / App Switcher
 * thumbnail as a side effect. Reliable back to Android API 1 — no version
 * gating needed, unlike [com.geekyants.device_shield.detection
 * .ScreenshotDetector]'s API-34 requirement.
 *
 * Deliberately its own file/package (`protection/`, not `detection/`) —
 * mirrors the Dart-side separation between detecting and blocking, which
 * are different concerns triggered differently (design doc §11: proactive
 * protection never touches the detection/policy pipeline at all).
 */
object ScreenCaptureProtection {
    fun enable(activity: Activity) {
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    fun disable(activity: Activity) {
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
