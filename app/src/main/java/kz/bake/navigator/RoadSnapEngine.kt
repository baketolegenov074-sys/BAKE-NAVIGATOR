package kz.bake.navigator

import android.location.Location
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.maplibre.android.geometry.LatLng
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlin.math.*

/**
 * Produces a separate display position snapped to a nearby drivable OSM road.
 * The original Android GPS fix is never modified and remains the source for
 * routing, speed, accuracy and off-route calculations.
 */
class RoadSnapEngine {
    private data class Segment(
        val lat1: Double, val lon1: Double,
        val lat2: Double, val lon2: Double
    )

    private val http = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .callTimeout(10, TimeUnit.SECONDS)
        .build()

    private var segments: List<Segment> = emptyList()
    private var cacheCenter: Location? = null
    private var lastFetchAt = 0L

    @Synchronized
    fun refreshRoads(location: Location) {
        val now = System.currentTimeMillis()
        val center = cacheCenter
        val moved = center == null || center.distanceTo(location) >= CACHE_MOVE_METERS
        if (!moved && now - lastFetchAt < CACHE_TTL_MS) return
        lastFetchAt = now

        try {
            val query = "[out:json][timeout:8];way(around:100,${location.latitude},${location.longitude})[\\"highway\\"];out tags geom;"
            val body = "data=" + URLEncoder.encode(query, "UTF-8")
            val loaded = http.newCall(
                Request.Builder()
                    .url("https://overpass-api.de/api/interpreter")
                    .post(body.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
                    .header("User-Agent", "BAKE-Navigator/1.0")
                    .build()
            ).execute().use { response ->
                if (!response.isSuccessful) return
                val elements = JSONObject(response.body?.string() ?: return)
                    .optJSONArray("elements") ?: return
                buildList {
                    for (i in 0 until elements.length()) {
                        val way = elements.optJSONObject(i) ?: continue
                        val tags = way.optJSONObject("tags") ?: continue
                        val highway = tags.optString("highway")
                        if (highway !in DRIVABLE_HIGHWAYS) continue
                        val geometry = way.optJSONArray("geometry") ?: continue
                        for (j in 0 until geometry.length() - 1) {
                            val a = geometry.optJSONObject(j) ?: continue
                            val b = geometry.optJSONObject(j + 1) ?: continue
                            val lat1 = a.optDouble("lat", Double.NaN)
                            val lon1 = a.optDouble("lon", Double.NaN)
                            val lat2 = b.optDouble("lat", Double.NaN)
                            val lon2 = b.optDouble("lon", Double.NaN)
                            if (lat1.isFinite() && lon1.isFinite() &&
                                lat2.isFinite() && lon2.isFinite()
                            ) add(Segment(lat1, lon1, lat2, lon2))
                        }
                    }
                }
            }
            if (loaded.isNotEmpty()) {
                segments = loaded
                cacheCenter = Location(location)
            }
        } catch (_: Exception) {
            // Keep the last usable road cache; GPS remains the fallback.
        }
    }

    @Synchronized
    fun snap(location: Location): LatLng? {
        if (segments.isEmpty() || !location.hasAccuracy() ||
            !location.accuracy.isFinite() || location.accuracy > MAX_ACCURACY_METERS
        ) return null

        val lat = location.latitude
        val lon = location.longitude
        val scaleY = METERS_PER_DEGREE
        val scaleX = scaleY * cos(Math.toRadians(lat))
        val moving = location.hasSpeed() && location.speed >= MIN_HEADING_SPEED_MPS
        val heading = if (moving && location.hasBearing()) location.bearing.toDouble() else null

        var bestDistance = Double.MAX_VALUE
        var bestLat = Double.NaN
        var bestLon = Double.NaN

        for (segment in segments) {
            val ax = (segment.lon1 - lon) * scaleX
            val ay = (segment.lat1 - lat) * scaleY
            val bx = (segment.lon2 - lon) * scaleX
            val by = (segment.lat2 - lat) * scaleY
            val dx = bx - ax
            val dy = by - ay
            val lengthSquared = dx * dx + dy * dy
            if (lengthSquared < 0.01) continue

            val t = (-(ax * dx + ay * dy) / lengthSquared).coerceIn(0.0, 1.0)
            val px = ax + t * dx
            val py = ay + t * dy
            val distance = hypot(px, py)
            if (distance >= bestDistance) continue

            if (heading != null) {
                val roadBearing = (Math.toDegrees(atan2(dx, dy)) + 360.0) % 360.0
                val difference = abs(((heading - roadBearing + 540.0) % 360.0) - 180.0)
                val bidirectionalDifference = minOf(difference, 180.0 - difference)
                if (bidirectionalDifference > MAX_HEADING_DIFFERENCE_DEGREES) continue
            }

            bestDistance = distance
            bestLat = lat + py / scaleY
            bestLon = lon + px / scaleX
        }

        val maxSnapDistance = if (moving) {
            minOf(MAX_MOVING_SNAP_METERS, maxOf(5.0, location.accuracy * 0.8))
        } else {
            minOf(MAX_STATIONARY_SNAP_METERS, maxOf(3.0, location.accuracy * 0.5))
        }
        if (bestDistance > maxSnapDistance || !bestLat.isFinite() || !bestLon.isFinite()) return null
        return LatLng(bestLat, bestLon)
    }

    private companion object {
        const val METERS_PER_DEGREE = 111320.0
        const val CACHE_TTL_MS = 30_000L
        const val CACHE_MOVE_METERS = 45f
        const val MAX_ACCURACY_METERS = 25f
        const val MIN_HEADING_SPEED_MPS = 2.5f
        const val MAX_HEADING_DIFFERENCE_DEGREES = 55.0
        const val MAX_MOVING_SNAP_METERS = 18.0
        const val MAX_STATIONARY_SNAP_METERS = 8.0
        val DRIVABLE_HIGHWAYS = setOf(
            "motorway", "motorway_link", "trunk", "trunk_link",
            "primary", "primary_link", "secondary", "secondary_link",
            "tertiary", "tertiary_link", "unclassified", "residential", "living_street",
            "service", "road"
        )
    }
}
