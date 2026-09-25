package com.geekyants.device_shield.detection

import android.app.Activity
import org.mockito.Mockito.mock
import org.mockito.Mockito.verifyNoInteractions
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/*
 * Exercises ScreenshotDetector.isSupported(sdkInt) (the pure version-check
 * logic) with synthetic inputs rather than the real android.os.Build
 * .VERSION.SDK_INT, which is a static field effectively unmockable in a
 * plain JVM unit test without Robolectric — the same constraint
 * EmulatorDetectorTest.kt/DebuggerDetectorTest.kt already document.
 *
 * Note: in this JVM test environment, the real Build.VERSION.SDK_INT reads
 * as its Java default (0), so ScreenshotDetector.isSupported (the real,
 * non-parameterized property) is always false here — meaning start()'s
 * actual API-34 registration path cannot be exercised end-to-end without
 * Robolectric. The start()/stop() tests below verify the no-op behavior
 * this environment's real SDK level produces, which is itself a real,
 * meaningful assertion (not a placeholder).
 */
internal class ScreenshotDetectorTest {
    @Test
    fun isSupported_belowApi34_isFalse() {
        assertFalse(ScreenshotDetector.isSupported(33))
        assertFalse(ScreenshotDetector.isSupported(21))
        assertFalse(ScreenshotDetector.isSupported(0))
    }

    @Test
    fun isSupported_api34AndAbove_isTrue() {
        assertTrue(ScreenshotDetector.isSupported(34))
        assertTrue(ScreenshotDetector.isSupported(35))
    }

    @Test
    fun start_onAnUnsupportedSdkLevel_neverRegistersACallback() {
        // This JVM's real Build.VERSION.SDK_INT is 0 (unsupported), so
        // start() must no-op rather than touching the Activity at all.
        val activity: Activity = mock(Activity::class.java)

        ScreenshotDetector.start(activity) {}

        verifyNoInteractions(activity)
    }

    @Test
    fun stop_whenNeverStarted_isSafeAndDoesNotThrow() {
        val activity: Activity = mock(Activity::class.java)

        ScreenshotDetector.stop(activity)

        verifyNoInteractions(activity)
    }
}
