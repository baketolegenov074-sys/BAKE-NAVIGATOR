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
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val worker: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var engine: Valhalla? = null

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
                        val config = ValhallaConfigFactory.usingTileExtract(tileFile.absolutePath)
                        val newEngine = Valhalla(appContext, config)
                        val oldEngine = engine
                        engine = newEngine
                        oldEngine?.close()
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
                worker.execute {
                    try {
                        val activeEngine = engine
                            ?: error("Valhalla is not initialized. Call initialize first.")
                        val locations = JSONArray()
                            .put(JSONObject().put("lat", startLat).put("lon", startLon).put("type", "break"))
                            .put(JSONObject().put("lat", endLat).put("lon", endLon).put("type", "break"))
                        val request = JSONObject()
                            .put("locations", locations)
                            .put("costing", "auto")
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

            "dispose" -> {
                worker.execute {
                    try {
                        engine?.close()
                        engine = null
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
        worker.execute {
            engine?.close()
            engine = null
        }
        worker.shutdown()
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }
}
