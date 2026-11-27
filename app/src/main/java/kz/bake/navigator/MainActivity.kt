package kz.bake.navigator

import android.Manifest
import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.location.LocationComponentActivationOptions
import org.maplibre.android.location.modes.CameraMode
import org.maplibre.android.location.modes.RenderMode
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.Property
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point
import java.util.concurrent.TimeUnit

class MainActivity : AppCompatActivity() {

    private lateinit var mapView: MapView
    private var mapLibreMap: MapLibreMap? = null
    private lateinit var tvDebug: TextView

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var currentLatLng: LatLng = LatLng(42.3417, 69.5901)
    private var gpsAccuracy: Float = 0f

    private var is3DMode = false
    private var startTimeMs = 0L
    private var loadTimeMs = 0L
    private var lastError = "Ошибок нет"

    private val styleUrl = "https://tiles.openfreemap.org/styles/liberty"
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private var routePoints: List<Point> = emptyList()
    private var simJob: Job? = null

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
                permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        if (granted) {
            enableLocationComponent()
            startGpsUpdates()
        } else {
            lastError = "Нет разрешения на GPS"
            updateDebugHud()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startTimeMs = System.currentTimeMillis()

        MapLibre.getInstance(this)
        setContentView(R.layout.activity_main)

        tvDebug = findViewById(R.id.tvDebug)
        mapView = findViewById(R.id.mapView)
        mapView.onCreate(savedInstanceState)

        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        setupMap()
        setupButtons()
    }

    private fun setupMap() {
        mapView.addOnDidFailLoadingMapListener { errorMessage ->
            lastError = "Сбой карты: $errorMessage (повтор через 2с)"
            updateDebugHud()
            Handler(Looper.getMainLooper()).postDelayed({
                loadMapStyle()
            }, 2000)
        }

        mapView.addOnDidFinishRenderingMapListener { fully ->
            if (fully && loadTimeMs == 0L) {
                loadTimeMs = System.currentTimeMillis() - startTimeMs
                lastError = "Карта готова"
                updateDebugHud()
            }
        }

        mapView.getMapAsync { map ->
            mapLibreMap = map

            val initialPosition = CameraPosition.Builder()
                .target(currentLatLng)
                .zoom(14.5)
                .tilt(0.0)
                .build()
            map.cameraPosition = initialPosition

            map.addOnMapLongClickListener { point ->
                Toast.makeText(this, "Строим маршрут...", Toast.LENGTH_SHORT).show()
                buildRoute(currentLatLng, point)
                true
            }

            loadMapStyle()
        }
    }

    private fun loadMapStyle() {
        val map = mapLibreMap ?: return
        map.setStyle(Style.Builder().fromUri(styleUrl)) { style ->
            initRouteLayers(style)
            checkPermissionsAndStartLocation()
        }
    }

    private fun initRouteLayers(style: Style) {
        if (style.getSource("route-source") == null) {
            style.addSource(GeoJsonSource("route-source"))
            val lineLayer = LineLayer("route-layer", "route-source").withProperties(
                PropertyFactory.lineColor(Color.parseColor("#1E88E5")),
                PropertyFactory.lineWidth(6f),
                PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND)
            )
            style.addLayer(lineLayer)
        }

        if (style.getSource("markers-source") == null) {
            style.addSource(GeoJsonSource("markers-source"))
            val circleLayer = CircleLayer("markers-layer", "markers-source").withProperties(
                PropertyFactory.circleColor(Color.parseColor("#E53935")),
                PropertyFactory.circleRadius(8f),
                PropertyFactory.circleStrokeColor(Color.WHITE),
                PropertyFactory.circleStrokeWidth(2f)
            )
            style.addLayer(circleLayer)
        }
    }

    private fun setupButtons() {
        findViewById<Button>(R.id.btnZoomIn).setOnClickListener {
            mapLibreMap?.animateCamera(CameraUpdateFactory.zoomIn())
        }

        findViewById<Button>(R.id.btnZoomOut).setOnClickListener {
            mapLibreMap?.animateCamera(CameraUpdateFactory.zoomOut())
        }

        findViewById<Button>(R.id.btnMyLocation).setOnClickListener {
            val map = mapLibreMap ?: return@setOnClickListener
            val pos = CameraPosition.Builder()
                .target(currentLatLng)
                .zoom(16.0)
                .tilt(if (is3DMode) 50.0 else 0.0)
                .build()
            map.animateCamera(CameraUpdateFactory.newCameraPosition(pos), 800)
            if (map.locationComponent.isLocationComponentActivated) {
                map.locationComponent.cameraMode = CameraMode.TRACKING_COMPASS
            }
        }

        findViewById<Button>(R.id.btnTilt).setOnClickListener {
            val map = mapLibreMap ?: return@setOnClickListener
            is3DMode = !is3DMode
            val targetTilt = if (is3DMode) 50.0 else 0.0
            val pos = CameraPosition.Builder()
                .target(map.cameraPosition.target)
                .zoom(map.cameraPosition.zoom)
                .tilt(targetTilt)
                .build()
            map.animateCamera(CameraUpdateFactory.newCameraPosition(pos), 500)
        }

        findViewById<Button>(R.id.btnClearRoute).setOnClickListener {
            simJob?.cancel()
            routePoints = emptyList()
            mapLibreMap?.getStyle { style ->
                style.getSourceAs<GeoJsonSource>("route-source")?.setGeoJson(LineString.fromLngLats(emptyList()))
                style.getSourceAs<GeoJsonSource>("markers-source")?.setGeoJson(Feature.fromGeometry(null))
            }
            lastError = "Маршрут очищен"
            updateDebugHud()
        }

        findViewById<Button>(R.id.btnSimulate).setOnClickListener {
            if (routePoints.isEmpty()) {
                Toast.makeText(this, "Зажмите палец на карте, чтобы задать финиш", Toast.LENGTH_LONG).show()
                return@setOnClickListener
            }
            startSimulation()
        }
    }

    private fun buildRoute(start: LatLng, end: LatLng) {
        mapLibreMap?.getStyle { style ->
            val destPoint = Point.fromLngLat(end.longitude, end.latitude)
            style.getSourceAs<GeoJsonSource>("markers-source")?.setGeoJson(Feature.fromGeometry(destPoint))
        }

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val url = "https://router.project-osrm.org/route/v1/driving/" +
                        "${start.longitude},${start.latitude};${end.longitude},${end.latitude}" +
                        "?overview=full&geometries=geojson"

                val request = Request.Builder().url(url).build()
                val response = httpClient.newCall(request).execute()
                val body = response.body?.string() ?: throw Exception("Пустой ответ OSRM")

                if (!response.isSuccessful) {
                    throw Exception("Ошибка OSRM: ${response.code}")
                }

                val json = JSONObject(body)
                val routes = json.getJSONArray("routes")
                if (routes.length() == 0) throw Exception("Маршрут не найден")

                val coords = routes.getJSONObject(0)
                    .getJSONObject("geometry")
                    .getJSONArray("coordinates")

                val points = ArrayList<Point>()
                for (i in 0 until coords.length()) {
                    val pair = coords.getJSONArray(i)
                    points.add(Point.fromLngLat(pair.getDouble(0), pair.getDouble(1)))
                }

                routePoints = points

                withContext(Dispatchers.Main) {
                    mapLibreMap?.getStyle { style ->
                        val lineString = LineString.fromLngLats(points)
                        style.getSourceAs<GeoJsonSource>("route-source")?.setGeoJson(lineString)
                    }
                    lastError = "Маршрут готов (${points.size} точек)"
                    updateDebugHud()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    lastError = "Ошибка маршрута: ${e.message}"
                    updateDebugHud()
                }
            }
        }
    }

    private fun startSimulation() {
        simJob?.cancel()
        is3DMode = true
        simJob = lifecycleScope.launch {
            lastError = "Тест-драйв запущен"
            updateDebugHud()
            for (i in routePoints.indices) {
                if (!isActive) break
                val pt = routePoints[i]
                val nextLatLng = LatLng(pt.latitude(), pt.longitude())
                currentLatLng = nextLatLng

                mapLibreMap?.getStyle { style ->
                    style.getSourceAs<GeoJsonSource>("markers-source")?.setGeoJson(Feature.fromGeometry(pt))
                }

                val cam = CameraPosition.Builder()
                    .target(nextLatLng)
                    .zoom(16.5)
                    .tilt(50.0)
                    .build()
                mapLibreMap?.animateCamera(CameraUpdateFactory.newCameraPosition(cam), 450)
                delay(500)
            }
            lastError = "Тест-драйв завершен"
            updateDebugHud()
        }
    }

    private fun checkPermissionsAndStartLocation() {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
        if (fine == PackageManager.PERMISSION_GRANTED || coarse == PackageManager.PERMISSION_GRANTED) {
            enableLocationComponent()
            startGpsUpdates()
        } else {
            locationPermissionLauncher.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun enableLocationComponent() {
        val map = mapLibreMap ?: return
        val style = map.style ?: return
        val locationComponent = map.locationComponent
        locationComponent.activateLocationComponent(
            LocationComponentActivationOptions.builder(this, style).build()
        )
        locationComponent.isLocationComponentEnabled = true
        locationComponent.cameraMode = CameraMode.NONE
        locationComponent.renderMode = RenderMode.COMPASS
    }

    @SuppressLint("MissingPermission")
    private fun startGpsUpdates() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2000L)
            .setMinUpdateIntervalMillis(1000L)
            .build()

        fusedLocationClient.requestLocationUpdates(request, object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                val loc = result.lastLocation ?: return
                currentLatLng = LatLng(loc.latitude, loc.longitude)
                gpsAccuracy = loc.accuracy
                updateDebugHud()
            }
        }, Looper.getMainLooper())
    }

    private fun updateDebugHud() {
        val loadText = if (loadTimeMs > 0) "${loadTimeMs} мс" else "загрузка..."
        tvDebug.text = "Старт карты: $loadText | GPS: ±${gpsAccuracy.toInt()}м\nСтатус: $lastError"
    }

    override fun onStart() { super.onStart(); mapView.onStart() }
    override fun onResume() { super.onResume(); mapView.onResume() }
    override fun onPause() { super.onPause(); mapView.onPause() }
    override fun onStop() { super.onStop(); mapView.onStop() }
    override fun onLowMemory() { super.onLowMemory(); mapView.onLowMemory() }
    override fun onDestroy() { super.onDestroy(); simJob?.cancel(); mapView.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) { super.onSaveInstanceState(outState); mapView.onSaveInstanceState(outState) }
}
