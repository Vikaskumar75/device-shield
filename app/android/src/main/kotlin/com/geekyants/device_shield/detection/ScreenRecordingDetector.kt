package com.geekyants.device_shield.detection

/**
 * Screenshot & Screen Recording Protection —
 * docs/features/SCREENSHOT_SCREEN_RECORDING_PROTECTION.md §7.1/§9.5.
 *
 * Android has no reliable discrete "recording started" signal a
 * third-party app can depend on — `FLAG_SECURE` (see
 * [com.geekyants.device_shield.protection.ScreenCaptureProtection]) blocks
 * captured *content*, but that is a side effect, not an observable event,
 * and package-visibility restrictions since Android 11 already rule out
 * the older `ActivityManager.getRunningServices()`-style heuristics some
 * SDKs historically relied on (design doc §7.1). This class exists
 * exclusively to return that answer honestly and consistently — never a
 * false, confident "not recording" — for every Android version, with no
 * version gating of its own (unlike [ScreenshotDetector], this isn't a
 * "not yet supported on old Android" limitation; it is a permanent
 * platform limitation, per design doc §1.6).
 *
 * No native push event is ever sent for this — `onScreenCaptureStateChanged`
 * is iOS-only (design doc §6.2); fabricating an Android push here would
 * contradict the "never a false answer" rule this class exists to uphold.
 */
object ScreenRecordingDetector {
    fun check(): Map<String, Any> = mapOf(
        "supported" to false,
        "isCaptured" to false,
        "reason" to "No reliable screen-recording signal exists on Android.",
    )
}
