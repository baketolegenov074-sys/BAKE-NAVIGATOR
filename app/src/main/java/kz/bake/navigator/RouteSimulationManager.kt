package kz.bake.navigator

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.maplibre.android.geometry.LatLng
import org.maplibre.geojson.Point
import kotlin.math.*

/** Route-only helpers. This class does not request or receive device location. */
class RouteSimulationManager(private val scope: CoroutineScope) {
    private var simulation: Job? = null

    var isSimulationActive = false
        private set

    fun distanceToRouteMeters(point: LatLng, route: List<Point>): Double {
        if (route.size < 2) return Double.POSITIVE_INFINITY
        val metersPerDegree = 111320.0
        val longitudeScale = metersPerDegree * cos(Math.toRadians(point.latitude))
        var minimum = Double.MAX_VALUE
        for (index in 0 until route.lastIndex) {
            val start = route[index]
            val end = route[index + 1]
            val ax = (start.longitude() - point.longitude) * longitudeScale
            val ay = (start.latitude() - point.latitude) * metersPerDegree
            val bx = (end.longitude() - point.longitude) * longitudeScale
            val by = (end.latitude() - point.latitude) * metersPerDegree
            val dx = bx - ax
            val dy = by - ay
            val denominator = dx * dx + dy * dy
            val fraction = if (denominator == 0.0) 0.0
                else (-(ax * dx + ay * dy) / denominator).coerceIn(0.0, 1.0)
            minimum = minOf(minimum, hypot(ax + fraction * dx, ay + fraction * dy))
        }
        return minimum
    }

    fun startSimulation(route: List<Point>, onPosition: (LatLng, Double) -> Unit, onFinished: () -> Unit) {
        stopSimulation()
        if (route.size < 2) return
        isSimulationActive = true
        simulation = scope.launch {
            try {
                for (index in route.indices) {
                    if (!isActive) break
                    val point = route[index]
                    val previousPoint = route[(index - 1).coerceAtLeast(0)]
                    val lat1 = Math.toRadians(previousPoint.latitude())
                    val lat2 = Math.toRadians(point.latitude())
                    val deltaLon = Math.toRadians(point.longitude() - previousPoint.longitude())
                    val y = sin(deltaLon) * cos(lat2)
                    val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
                    val bearing = (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
                    onPosition(LatLng(point.latitude(), point.longitude()), bearing)
                    delay(220L)
                }
            } finally {
                isSimulationActive = false
                onFinished()
            }
        }
    }

    fun stopSimulation() {
        simulation?.cancel()
        simulation = null
        isSimulationActive = false
    }

    fun release() = stopSimulation()
}
