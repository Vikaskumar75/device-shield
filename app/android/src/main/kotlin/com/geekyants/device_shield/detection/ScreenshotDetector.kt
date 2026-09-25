package com.geekyants.device_shield.detection

import android.app.Activity
import android.os.Build

/**
 * Screenshot & Screen Recording Protection —
 * doc/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §7.1/§9.5.
 *
 * Push-only: unlike [EmulatorDetector]/[DebuggerDetector], there is no
 * meaningful request/response "check" for this — a screenshot is a discrete
 * past event, not a stable state to poll. This class only ever calls
 * [onScreenshotTaken] the moment the OS reports one; it exposes no
 * MethodChannel-facing `check()` of its own (no MethodCode exists for one —
 * confirmed absent from Step 4's `method_codes.dart`, and intentionally not
 * added here since Step 5 is bridge/native only, not a Dart-detector
 * change).
 *
 * Android 14 (API 34, `UPSIDE_DOWN_CAKE`) only, by design decision recorded
 * in Step 5's Architecture Verification Report: `Activity
 * .registerScreenCaptureCallback()` is the only *reliable* Android
 * screenshot signal (design doc §7.1). The pre-14 `MediaStore`
 * `ContentObserver` heuristic described in the same section is deliberately
 * **not implemented** here — it requires `READ_MEDIA_IMAGES`/
 * `READ_EXTERNAL_STORAGE` — a *runtime* permission, with a user-facing
 * prompt, that this plugin does not declare and was explicitly instructed
 * not to add silently. Below API 34, [isSupported] is `false` and [start]
 * is a no-op — never a fabricated "no screenshot occurred" signal,
 * matching this feature's own "never a false, confident answer" rule
 * (design doc §13).
 *
 * The API-34 callback is itself permission-gated:
 * `registerScreenCaptureCallback` throws `SecurityException` without
 * `android.permission.DETECT_SCREEN_CAPTURE`. That one *is* declared, in
 * this plugin's own `AndroidManifest.xml` — a normal, install-time
 * permission that merges into the host app automatically and raises no
 * prompt, so it carries none of the cost that kept the pre-14 heuristic's
 * runtime permission out. [start] catches `SecurityException` regardless:
 * a host app can strip a merged permission with `tools:node="remove"`, and
 * this runs from an Activity lifecycle callback, where throwing would take
 * the host app down.
 */
object ScreenshotDetector {
    private var callback: Activity.ScreenCaptureCallback? = null

    /** Pure version check, separated from the real [Build.VERSION.SDK_INT]
     * read below so it can be unit-tested with synthetic inputs — the same
     * constraint [EmulatorDetector]/[DebuggerDetector] already document for
     * `Build.*`/`Debug.*`. */
    internal fun isSupported(sdkInt: Int): Boolean = sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    val isSupported: Boolean
        get() = isSupported(Build.VERSION.SDK_INT)

    /**
     * Begins observing [activity] for screenshots, if supported. A no-op
     * (not an error) below API 34, and a no-op if already observing —
     * matches [ScreenCaptureProtection]'s own idempotent shape.
     */
    fun start(activity: Activity, onScreenshotTaken: () -> Unit) {
        if (!isSupported) return
        if (callback != null) return

        val newCallback = Activity.ScreenCaptureCallback { onScreenshotTaken() }
        try {
            activity.registerScreenCaptureCallback(activity.mainExecutor, newCallback)
        } catch (e: SecurityException) {
            // DETECT_SCREEN_CAPTURE is declared in this plugin's own
            // manifest and merges into the host app automatically, so the
            // normal path never lands here. A host app can still strip it
            // (`tools:node="remove"`), and OEM builds have been known to
            // gate it differently. Degrade to "no screenshot detection"
            // rather than taking the host app down from a lifecycle
            // callback — the same "never crash the host, never fabricate a
            // signal" rule the rest of this feature follows.
            return
        } catch (e: IllegalStateException) {
            // Activity already destroyed / not in a registerable state.
            return
        }
        // Assigned only after registration actually succeeded, so a failed
        // start() leaves no stale callback for stop() to unregister.
        callback = newCallback
    }

    /** Stops observing. Safe to call even if [start] was never called, or
     * already stopped. */
    fun stop(activity: Activity) {
        val existing = callback ?: return
        callback = null
        try {
            activity.unregisterScreenCaptureCallback(existing)
        } catch (e: SecurityException) {
            // Symmetric with start(): never throw out of a lifecycle
            // callback. The field is already cleared above, so this
            // detector is left consistently "not observing" either way.
        } catch (e: IllegalStateException) {
        }
    }
}
