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
 * Standalone GPS engine for BAKE Navigator Test.
 *
 * Uses the device GPS provider directly. It does not use fused location,
 * cached positions, route snapping, coordinate averaging, or another app's code.
 * Every accepted fix is the unmodified Android GPS location.
 */
class IndependentGpsEngine(context: Context) {
    private val appContext = context.applicationContext
    private val locationManager =
        appContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var listener: LocationListener? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var lastElapsedRealtimeNanos = 0L
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
            // Register exactly one listener for hardware-backed GNSS/GPS fixes.
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                0f,
                newListener,
                Looper.getMainLooper()
            )
            registerGnssDiagnostics()
        } catch (error: SecurityException) {
            listener = null
            onError("Нет разрешения на точное местоположение")
        } catch (error: IllegalArgumentException) {
            listener = null
            onError("GPS_PROVIDER недоступен: ${error.message ?: "ошибка Android"}")
        } catch (error: Exception) {
            listener = null
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

        // Do not average, shift, snap, or delay the hardware GPS coordinates.
        val fix = Location(location)
        lastElapsedRealtimeNanos = timestamp
        speedKmh = if (fix.hasSpeed() && fix.speed.isFinite()) {
            (fix.speed * 3.6f).coerceAtLeast(0f)
        } else {
            0f
        }

        onFix(fix, LatLng(latitude, longitude))
    }

    private fun registerGnssDiagnostics() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (gnssCallback != null) return

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
        speedKmh = 0f
        satellitesVisible = 0
        satellitesUsedInFix = 0
    }

    fun release() {
        stopGps()
    }
}
