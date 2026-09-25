package com.geekyants.device_shield.detection

import android.app.AppOpsManager
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Process
import android.provider.Settings

/**
 * FR-06: heuristic mock/spoofed GPS location detection via four
 * independent signal categories (Android) plus the shared
 * [impossibleVelocity] check — the same signal-count confidence model
 * [RootDetector]/[EmulatorDetector]/[DebuggerDetector] already use.
 * docs/features/MOCK_LOCATION_DETECTION.md.
 *
 * Unlike root/jailbreak, "mock location" is a real concept on both
 * platforms, so this never reports `applicable: false`. What it does
 * honestly report is an Android-only capability gap: the strongest
 * signal, [mockProviderFlag], needs `ACCESS_FINE_LOCATION`/
 * `ACCESS_COARSE_LOCATION` already granted and at least one cached
 * location fix to inspect. This SDK deliberately never requests that
 * permission itself — no detector or protection in this codebase
 * requests a dangerous runtime permission, and adding that plumbing is
 * out of scope for this detector alone (see
 * `lib/src/permission/default_permission_manager.dart`). [check] only
 * reads whatever grant state already exists via the plain
 * [Context.checkPermission] API (no `androidx.core` dependency needed —
 * this plugin adds none today, the same restraint [RootDetector] keeps)
 * and degrades gracefully — `permissionGranted`/`locationAvailable` in
 * the result carry that gap forward instead of a silently confident
 * "not detected".
 *
 * Two categories are documented, deliberately, as weaker than the rest:
 * - [mockAppSelectedForThisApp]: Android's per-app mock-location model
 *   (since API 23) only lets an app learn whether *it itself* was
 *   selected as the system mock-location app in Developer Options — the
 *   OS deliberately does not expose which *other* app holds that role.
 *   A `false` here is not proof no other app is mocking location.
 * - [legacyAllowMockLocationSetting]: `Settings.Secure
 *   .ALLOW_MOCK_LOCATION` was the pre-Marshmallow single global toggle,
 *   superseded by the per-app model above on API 23+; reading it on a
 *   modern OS would be misleading, so it is simply never evaluated
 *   there (always `false` on API 23+, not a real negative signal).
 *
 * Deliberately excludes a "Developer Options enabled" signal — that is
 * FR-05's entire scope ([DeveloperOptionsDetector], not yet built);
 * duplicating it here would overlap a separately planned detector, the
 * same non-duplication precedent `JailbreakDetector.swift` already sets
 * for not scanning for runtime hooks itself (FR-07's scope).
 */
object MockLocationDetector {
    private val FAKE_GPS_PACKAGES = listOf(
        "com.lexa.fakegps",
        "com.incorporateapps.fakegps.fre",
        "com.blogspot.newapphorizons.fakegps",
        "com.gsmartstudio.fakegps",
        "com.evezzon.fakegps",
        "com.rosteam.gpsemulator",
        "com.fakegps.mock",
        "com.theappninjas.fakegpsjoystick",
        "com.jinseiapp.fakegps",
        "ru.gavrikov.mocklocations",
    )

    private const val OPSTR_MOCK_LOCATION = "android:mock_location"

    // mockProviderFlag, fakeGpsAppInstalled, mockAppSelectedForThisApp,
    // legacyAllowMockLocationSetting, impossibleVelocity.
    private const val SIGNAL_CATEGORY_COUNT = 5.0

    // Minimum physically-implausible speed, in meters/second, above
    // which two consecutive fixes are flagged as an impossible "teleport"
    // (~1080 km/h — well above commercial air travel ground speed, so a
    // real device should never legitimately trigger this).
    private const val IMPOSSIBLE_SPEED_MPS = 300.0

    // Below these deltas, ordinary GPS drift on a stationary device can
    // look like fast "movement" — too small a distance/time to say
    // anything meaningful about speed, so the check is skipped entirely
    // rather than risk a false positive from jitter.
    private const val MIN_DISTANCE_METERS = 10.0
    private const val MIN_TIME_SECONDS = 3.0

    // In-memory only, per process — reset on app restart, expected (same
    // "expected false-negative" framing RootDetector documents for
    // systemless Magisk). Never persisted; this is a live, resettable
    // heuristic, not a durable record.
    @Volatile
    private var lastFix: Triple<Double, Double, Long>? = null

    fun check(context: Context): Map<String, Any> {
        val permissionGranted = isLocationPermissionGranted(context)
        val mostRecentFix = if (permissionGranted) mostRecentLocation(context) else null

        val velocityResult = mostRecentFix?.let {
            evaluateVelocity(it.latitude, it.longitude, it.time)
        } ?: false

        return evaluate(
            permissionGranted = permissionGranted,
            locationAvailable = mostRecentFix != null,
            mockProviderFlag = mostRecentFix?.isFromMockProvider ?: false,
            fakeGpsAppInstalled = anyPackageInstalled(context, FAKE_GPS_PACKAGES),
            mockAppSelectedForThisApp = isThisAppSelectedAsMockLocationApp(context),
            legacyAllowMockLocationSetting = isLegacyMockLocationSettingEnabled(context),
            impossibleVelocity = velocityResult,
        )
    }

    /**
     * Pure decision logic, separated from the real LocationManager/
     * PackageManager/AppOpsManager/Settings reads in [check] above so it
     * can be unit-tested with synthetic inputs — the same split
     * [RootDetector]/[EmulatorDetector] already document for their own
     * reasons.
     */
    internal fun evaluate(
        permissionGranted: Boolean,
        locationAvailable: Boolean,
        mockProviderFlag: Boolean,
        fakeGpsAppInstalled: Boolean,
        mockAppSelectedForThisApp: Boolean,
        legacyAllowMockLocationSetting: Boolean,
        impossibleVelocity: Boolean,
    ): Map<String, Any> {
        val signals = mutableListOf<String>()

        if (mockProviderFlag) signals.add("mock_provider_flag")
        if (fakeGpsAppInstalled) signals.add("fake_gps_app_installed")
        if (mockAppSelectedForThisApp) signals.add("mock_app_selected_for_this_app")
        if (legacyAllowMockLocationSetting) signals.add("legacy_allow_mock_location_setting")
        if (impossibleVelocity) signals.add("impossible_velocity")

        val confidence = (signals.size / SIGNAL_CATEGORY_COUNT).coerceAtMost(1.0)
        return mapOf(
            "detected" to signals.isNotEmpty(),
            "confidence" to confidence,
            "signals" to signals,
            "applicable" to true,
            "permissionGranted" to permissionGranted,
            "locationAvailable" to locationAvailable,
        )
    }

    private fun isLocationPermissionGranted(context: Context): Boolean {
        val pid = Process.myPid()
        val uid = Process.myUid()
        val fine = context.checkPermission(
            android.Manifest.permission.ACCESS_FINE_LOCATION,
            pid,
            uid,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = context.checkPermission(
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
            pid,
            uid,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    /**
     * Passive read only — [LocationManager.getLastKnownLocation] never
     * requests a fresh fix or registers a listener, unlike
     * `requestLocationUpdates`. That keeps [check] synchronous like every
     * other detector in this SDK, at the cost of possibly returning a
     * stale or entirely absent fix (no provider has produced one yet, or
     * location services are off at the OS level) — both collapse to the
     * same honest `locationAvailable: false` rather than a confident
     * "not detected".
     */
    private fun mostRecentLocation(context: Context): Location? {
        val locationManager =
            context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return null

        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )

        return providers.mapNotNull { provider ->
            try {
                locationManager.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                // Permission revoked between the checkSelfPermission call
                // above and this read (a real, if narrow, TOCTOU window) —
                // treat exactly like "no fix available", never crash.
                null
            } catch (e: IllegalArgumentException) {
                // Provider not present on this device (e.g. no GPS
                // hardware) — same honest "no fix from this provider".
                null
            }
        }.maxByOrNull { it.time }
    }

    /**
     * Requires `<queries><package android:name="..."/></queries>` entries
     * in this plugin's own AndroidManifest.xml — the same Android 11+
     * (API 30) requirement [RootDetector.anyPackageInstalled] already
     * documents.
     */
    private fun anyPackageInstalled(context: Context, packages: List<String>): Boolean {
        val packageManager = context.packageManager
        return packages.any { packageName ->
            try {
                packageManager.getPackageInfo(packageName, 0)
                true
            } catch (e: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    /**
     * Hardcoded op string rather than [AppOpsManager]'s own
     * `OPSTR_MOCK_LOCATION` constant — that constant is `@SystemApi`
     * (hidden), but the string literal itself is stable AOSP and
     * [AppOpsManager.checkOpNoThrow] is public, so no reflection into
     * hidden APIs is needed (the same restraint `RootDetector
     * .isDangerousPropSet` documents for avoiding hidden
     * `SystemProperties` reflection).
     */
    private fun isThisAppSelectedAsMockLocationApp(context: Context): Boolean {
        return try {
            val appOps =
                context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
                    ?: return false
            appOps.checkOpNoThrow(
                OPSTR_MOCK_LOCATION,
                Process.myUid(),
                context.packageName,
            ) == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun isLegacyMockLocationSettingEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Superseded by the per-app model on API 23+ — evaluating
            // this setting there would be misleading, not a real signal.
            return false
        }
        @Suppress("DEPRECATION")
        return try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ALLOW_MOCK_LOCATION,
            ) == "1"
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Stateful by design — compares this fix against [lastFix] from a
     * previous [check] call on this same process. The very first call
     * ever made has nothing to compare against, so it neither fires nor
     * counts as a clean signal; it simply seeds [lastFix] for the next
     * call. Deltas below [MIN_DISTANCE_METERS]/[MIN_TIME_SECONDS] are
     * ignored outright to avoid ordinary GPS jitter on a stationary
     * device reading as "teleportation". A manipulated system clock could
     * mask or inflate the computed speed either way — a known,
     * unaddressed weak point, the same class of caveat `RootDetector`
     * documents for `build_tags_test_keys`.
     */
    private fun evaluateVelocity(lat: Double, lon: Double, timeMs: Long): Boolean {
        val previous = lastFix
        lastFix = Triple(lat, lon, timeMs)

        if (previous == null) return false
        val (prevLat, prevLon, prevTimeMs) = previous

        val elapsedSeconds = (timeMs - prevTimeMs) / 1000.0
        if (elapsedSeconds < MIN_TIME_SECONDS) return false

        val distanceMeters = haversineMeters(prevLat, prevLon, lat, lon)
        if (distanceMeters < MIN_DISTANCE_METERS) return false

        val speedMps = distanceMeters / elapsedSeconds
        return speedMps > IMPOSSIBLE_SPEED_MPS
    }

    private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadiusMeters = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return earthRadiusMeters * c
    }
}
