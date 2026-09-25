package com.geekyants.device_shield.detection

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Debug

/**
 * FR-04 (SRS section 5.4): debugger detection via the official Android
 * debugger-state APIs plus the app's own debuggable-build flag. Every
 * signal is independently weak evidence on its own (a debuggable build
 * isn't necessarily being actively debugged right now); confidence is
 * proportional to how many fire at once, matching EmulatorDetector's own
 * signal-count-based confidence model.
 */
object DebuggerDetector {
    private const val SIGNAL_CATEGORY_COUNT = 3.0

    fun check(context: Context): Map<String, Any> = evaluate(
        debuggerConnected = Debug.isDebuggerConnected(),
        waitingForDebugger = Debug.waitingForDebugger(),
        debuggableFlag = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    )

    /**
     * Pure decision logic, separated from the actual `android.os.Debug`
     * calls and `Context` read in [check] above so it can be unit-tested
     * with synthetic inputs — `Debug.isDebuggerConnected()` and friends
     * are static Android-framework calls that throw in a plain JVM unit
     * test without Robolectric, the same constraint `EmulatorDetector.kt`
     * already documents for `Build.*` fields.
     */
    internal fun evaluate(
        debuggerConnected: Boolean,
        waitingForDebugger: Boolean,
        debuggableFlag: Boolean
    ): Map<String, Any> {
        val signals = mutableListOf<String>()

        if (debuggerConnected) {
            signals.add("debugger_connected")
        }
        if (waitingForDebugger) {
            signals.add("waiting_for_debugger")
        }
        if (debuggableFlag) {
            signals.add("debuggable_flag")
        }

        val confidence = (signals.size / SIGNAL_CATEGORY_COUNT).coerceAtMost(1.0)
        return mapOf(
            "detected" to signals.isNotEmpty(),
            "confidence" to confidence,
            "signals" to signals
        )
    }
}
