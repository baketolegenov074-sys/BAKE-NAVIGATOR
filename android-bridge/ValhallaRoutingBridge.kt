package kz.bake.bake_navigator

import android.os.Handler
import android.os.Looper
import com.valhalla.valhalla.config.ValhallaConfigFactory
import com.valhalla.valhalla.Valhalla
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Offline Valhalla bridge for Flutter.
 *
 * The class is deliberately independent of MainActivity so the generated Flutter
 * Android project can register it after `flutter create` in CI.
 *
 * Expected calls:
 *  - initialize(tileExtractPath: String)
 *  - route(startLat: Double, startLon: Double, endLat: Double, endLon: Double)
 *  - dispose()
 *
 * route() returns the raw OSRM-compatible JSON string. Dart can decode it with
 * jsonDecode and keep using the existing route parser.
 */
class ValhallaRoutingBridge(
    private val messenger: BinaryMessenger,
    private val appContext: android.content.Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "bake.navigator/valhalla"

        // One process-wide engine and worker: recreating a FlutterActivity or
        // its MethodChannel must not reload the on-device road graph.
        private val worker: ExecutorService = Executors.newSingleThreadExecutor()
        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        private var engine: Valhalla? = null

        @Volatile
        private var initializedTilePath: String? = null
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val tilePath = call.argument<String>("tileExtractPath")
                if (tilePath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "tileExtractPath is required", null)
                    return
                }
                worker.execute {
                    try {
                        val tileFile = File(tilePath)
                        require(tileFile.isAbsolute && tileFile.isFile) {
                            "Valhalla tile extract was not found: $tilePath"
                        }
                        val activeEngine = engine
                        if (activeEngine == null || initializedTilePath != tileFile.absolutePath) {
                            val config = ValhallaConfigFactory.usingTileExtract(tileFile.absolutePath)
                            val newEngine = Valhalla(appContext, config)
                            val oldEngine = engine
                            engine = newEngine
                            initializedTilePath = tileFile.absolutePath
                            oldEngine?.close()
                        }
                        postSuccess(result, mapOf("ready" to true))
                    } catch (error: Exception) {
                        postError(result, "VALHALLA_INIT_FAILED", error.message ?: error.javaClass.simpleName)
                    }
                }
            }

            "route" -> {
                val startLat = call.argument<Double>("startLat")
                val startLon = call.argument<Double>("startLon")
                val endLat = call.argument<Double>("endLat")
                val endLon = call.argument<Double>("endLon")
                val coordinates = listOf(startLat, startLon, endLat, endLon)
                if (coordinates.any { it == null || !it.isFinite() }) {
                    result.error("INVALID_ARGUMENT", "Four finite coordinates are required", null)
                    return
                }
                val requestedCosting = call.argument<String>("costing") ?: "auto"
                val costing = if (requestedCosting == "pedestrian") "pedestrian" else "auto"
                worker.execute {
                    try {
                        val activeEngine = engine
                            ?: error("Valhalla is not initialized. Call initialize first.")
                        val locations = JSONArray()
                            .put(JSONObject().put("lat", startLat).put("lon", startLon).put("type", "break"))
                            .put(JSONObject().put("lat", endLat).put("lon", endLon).put("type", "break"))
                        val costingOptions = JSONObject()
                        if (costing == "auto") {
                            costingOptions.put("auto", JSONObject().put("shortest", true))
                        } else {
                            costingOptions.put("pedestrian", JSONObject())
                        }
                        val request = JSONObject()
                            .put("locations", locations)
                            .put("alternates", 2)
                            .put("costing", costing)
                            .put("costing_options", costingOptions)
                            .put("format", "osrm")
                            .put("shape_format", "geojson")
                            .toString()
                        val responseJson = activeEngine.routeRaw(request)
                        postSuccess(result, responseJson)
                    } catch (error: Exception) {
                        postError(result, "VALHALLA_ROUTE_FAILED", error.message ?: error.javaClass.simpleName)
                    }
                }
            }

            "traceRoute" -> {
                val requestJson = call.argument<String>("requestJson")
                if (requestJson.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "requestJson is required", null)
                    return
                }
                try {
                    val request = JSONObject(requestJson)
                    val shape = request.optJSONArray("shape")
                    require(shape != null && shape.length() >= 2) {
                        "At least two GPS trace points are required"
                    }
                } catch (error: Exception) {
                    result.error("INVALID_ARGUMENT", error.message ?: "Invalid trace request", null)
                    return
                }
                worker.execute {
                    try {
                        val activeEngine = engine
                            ?: error("Valhalla is not initialized. Call initialize first.")
                        val response = JSONObject(activeEngine.traceRouteRaw(requestJson))
                        val trip = response.optJSONObject("trip")
                            ?: error("Valhalla map matching returned no trip")
                        val legs = trip.optJSONArray("legs")
                            ?: error("Valhalla map matching returned no legs")
                        require(legs.length() > 0) { "Valhalla map matching returned an empty path" }
                        val lastLeg = legs.getJSONObject(legs.length() - 1)
                        val encodedShape = lastLeg.optString("shape")
                        val point = decodePolyline6LastPoint(encodedShape)
                            ?: error("Valhalla map matching returned an invalid road shape")
                        postSuccess(result, point)
                    } catch (error: Exception) {
                        postError(result, "VALHALLA_TRACE_FAILED", error.message ?: error.javaClass.simpleName)
                    }
                }
            }

            "dispose" -> {
                worker.execute {
                    try {
                        engine?.close()
                        engine = null
                        initializedTilePath = null
                        postSuccess(result, mapOf("disposed" to true))
                    } catch (error: Exception) {
                        postError(result, "VALHALLA_DISPOSE_FAILED", error.message ?: error.javaClass.simpleName)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
    }

    private fun decodePolyline6LastPoint(encoded: String): Map<String, Double>? {
        if (encoded.isEmpty()) return null
        var index = 0
        var latitude = 0L
        var longitude = 0L
        var lastLatitude: Long? = null
        var lastLongitude: Long? = null

        fun readDelta(): Long {
            var result = 0L
            var shift = 0
            var chunk: Int
            do {
                require(index < encoded.length) { "Truncated Valhalla polyline" }
                chunk = encoded[index++].code - 63
                require(chunk in 0..63) { "Invalid Valhalla polyline character" }
                result = result or ((chunk and 0x1f).toLong() shl shift)
                shift += 5
                require(shift <= 60) { "Valhalla polyline delta overflow" }
            } while (chunk >= 0x20)
            return if ((result and 1L) != 0L) (result shr 1).inv() else result shr 1
        }

        while (index < encoded.length) {
            latitude += readDelta()
            longitude += readDelta()
            lastLatitude = latitude
            lastLongitude = longitude
        }
        val lat = lastLatitude ?: return null
        val lon = lastLongitude ?: return null
        return mapOf("lat" to lat / 1_000_000.0, "lon" to lon / 1_000_000.0)
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }
}
