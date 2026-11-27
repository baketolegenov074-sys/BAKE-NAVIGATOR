package kz.bake.navigator

import android.annotation.SuppressLint
import android.content.Context
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import org.maplibre.android.geometry.LatLng
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Independent Android GNSS receiver.
 *
 * Publishes original Android coordinates only after basic quality and
 * physically-plausible movement checks. It does not snap to roads/routes
 * or average coordinates.
 */
class IndependentGpsEngine(context: Context) {
    private val appContext = context.applicationContext
    private val locationManager =
        appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var listener: LocationListener? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var lastElapsedRealtimeNanos = 0L
    private var lastAcceptedLocation: Location? = null

    var speedKmh: Float = 0f
        private set
    var satellitesVisible: Int = 0
        private set
    var satellitesUsedInFix: Int = 0
        private set

    @SuppressLint("MissingPermission")
    fun start(onFix: (Location, LatLng) -> Unit, onError: (String) -> Unit) {
        if (listener != null) return

        if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            onError("GPS отключён на устройстве")
            return
        }

        lastElapsedRealtimeNanos = 0L
        lastAcceptedLocation = null
        speedKmh = 0f
        satellitesVisible = 0
        satellitesUsedInFix = 0

        val newListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                publishGpsFix(location, onFix)
            }

            @Deprecated("Deprecated by Android")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) {
                if (provider == LocationManager.GPS_PROVIDER) {
                    onError("GPS отключён на устройстве")
                }
            }
        }

        listener = newListener
        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                0f,
                newListener,
                Looper.getMainLooper()
            )
            registerGnssDiagnostics()
        } catch (error: SecurityException) {
            stopGps()
            onError("Нет разрешения на точное местоположение")
        } catch (error: IllegalArgumentException) {
            stopGps()
            onError("GPS_PROVIDER недоступен: ${error.message ?: "ошибка Android"}")
        } catch (error: Exception) {
            stopGps()
            onError("Не удалось запустить GPS: ${error.message ?: "ошибка Android"}")
        }
    }

    private fun publishGpsFix(
        location: Location,
        onFix: (Location, LatLng) -> Unit
    ) {
        val latitude = location.latitude
        val longitude = location.longitude
        val timestamp = location.elapsedRealtimeNanos

        if (!latitude.isFinite() || !longitude.isFinite()) return
        if (latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return
        if (timestamp <= 0L || timestamp <= lastElapsedRealtimeNanos) return

        // Do not put visibly inaccurate GPS fixes on the map.
        if (!location.hasAccuracy() || !location.accuracy.isFinite() ||
            location.accuracy <= 0f || location.accuracy > MAX_ACCEPTED_ACCURACY_METERS
        ) return

        val previous = lastAcceptedLocation
        if (previous != null) {
            val elapsedSeconds =
                (timestamp - previous.elapsedRealtimeNanos) / NANOS_PER_SECOND
            if (elapsedSeconds <= 0.0) return

            // Reject implausible one-to-three-second teleports. Longer gaps are
            // not constrained because the vehicle may genuinely have moved.
            if (elapsedSeconds <= MAX_JUMP_CHECK_INTERVAL_SECONDS) {
                val distance = previous.distanceTo(location).toDouble()
                val accuracyAllowance =
                    (previous.accuracy.coerceAtMost(20f) +
                        location.accuracy.coerceAtMost(20f)) * 0.75 + 8.0
                val allowedDistance =
                    maxOf(MIN_MOVEMENT_ALLOWANCE_METERS,
                        MAX_PLAUSIBLE_SPEED_MPS * elapsedSeconds + accuracyAllowance)
                if (distance > allowedDistance) return
            }
        }

        val fix = Location(location)
        lastElapsedRealtimeNanos = timestamp
        lastAcceptedLocation = fix
        speedKmh = if (fix.hasSpeed() && fix.speed.isFinite()) {
            (fix.speed * 3.6f).coerceAtLeast(0f)
        } else {
            0f
        }

        // The accepted coordinates remain the original Android GPS fix.
        onFix(fix, LatLng(latitude, longitude))
    }

    private fun registerGnssDiagnostics() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || gnssCallback != null) return

        val callback = object : GnssStatus.Callback() {
            override fun onSatelliteStatusChanged(status: GnssStatus) {
                var visible = 0
                var used = 0
                for (index in 0 until status.satelliteCount) {
                    visible++
                    if (status.usedInFix(index)) used++
                }
                satellitesVisible = visible
                satellitesUsedInFix = used
            }
        }
        gnssCallback = callback
        try {
            @Suppress("DEPRECATION")
            locationManager.registerGnssStatusCallback(callback, mainHandler)
        } catch (_: Exception) {
            gnssCallback = null
        }
    }

    fun stopGps() {
        listener?.let { activeListener ->
            try {
                locationManager.removeUpdates(activeListener)
            } catch (_: Exception) {
            }
        }
        listener = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            gnssCallback?.let { callback ->
                try {
                    locationManager.unregisterGnssStatusCallback(callback)
                } catch (_: Exception) {
                }
            }
        }
        gnssCallback = null
        lastElapsedRealtimeNanos = 0L
        lastAcceptedLocation = null
        speedKmh = 0f
        satellitesVisible = 0
        satellitesUsedInFix = 0
    }

    fun release() {
        stopGps()
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val MAX_ACCEPTED_ACCURACY_METERS = 35f
        const val MAX_JUMP_CHECK_INTERVAL_SECONDS = 3.0
        const val MAX_PLAUSIBLE_SPEED_MPS = 40.0
        const val MIN_MOVEMENT_ALLOWANCE_METERS = 30.0
    }
}
