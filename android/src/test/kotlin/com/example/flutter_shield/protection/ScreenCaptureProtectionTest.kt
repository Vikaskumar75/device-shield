package com.example.flutter_shield.protection

import android.app.Activity
import android.view.Window
import android.view.WindowManager
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import kotlin.test.Test

internal class ScreenCaptureProtectionTest {
    private fun activityWithMockWindow(): Pair<Activity, Window> {
        val activity: Activity = mock(Activity::class.java)
        val window: Window = mock(Window::class.java)
        `when`(activity.window).thenReturn(window)
        return activity to window
    }

    @Test
    fun enable_setsFlagSecureOnTheActivitysWindow() {
        val (activity, window) = activityWithMockWindow()

        ScreenCaptureProtection.enable(activity)

        verify(window).addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    @Test
    fun disable_clearsFlagSecureFromTheActivitysWindow() {
        val (activity, window) = activityWithMockWindow()

        ScreenCaptureProtection.disable(activity)

        verify(window).clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
