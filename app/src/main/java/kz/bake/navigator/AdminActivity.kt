package kz.bake.navigator

import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.*
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.geometry.LatLng

class AdminActivity : AppCompatActivity() {
    private lateinit var mapView: MapView
    private lateinit var map: MapLibreMap
    private lateinit var category: Spinner
    private lateinit var status: TextView
    private lateinit var saveButton: Button
    private lateinit var listButton: Button
    private val categories = arrayOf(
        "Камера", "Знак ограничения скорости", "Другой дорожный знак",
        "Пешеходный переход", "Светофор", "Опасный участок",
        "Железнодорожный переезд", "Запрещённый поворот", "Разворот запрещён",
        "Одностороннее движение", "Дорожные работы", "Перекрытие дороги", "Школа"
    )
    private val prefs by lazy { getSharedPreferences("bake_admin_objects_v1", MODE_PRIVATE) }
    private val objects = JSONArray()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MapEngineManager.initializeSdk(this)
        loadObjects()
        val root = FrameLayout(this)
        mapView = MapView(this)
        root.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        val crosshair = TextView(this).apply {
            text = "⊕"
            textSize = 42f
            setTextColor(Color.rgb(211, 47, 47))
            gravity = Gravity.CENTER
            elevation = 8f
        }
        root.addView(crosshair, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))

        val top = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(12, 12, 12, 8)
            setBackgroundColor(Color.WHITE)
            elevation = 10f
        }
        val title = TextView(this).apply {
            text = "КАБИНЕТ АДМИНИСТРАТОРА"
            textSize = 17f
            setTextColor(Color.BLACK)
            setPadding(4, 4, 4, 10)
        }
        category = Spinner(this)
        category.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, categories)
        status = TextView(this).apply {
            text = "Переместите карту: точка под прицелом"
            textSize = 12f
            setTextColor(Color.DKGRAY)
            setPadding(4, 8, 4, 4)
        }
        top.addView(title)
        top.addView(category)
        top.addView(status)
        root.addView(top, FrameLayout.LayoutParams(-1, -2, Gravity.TOP))

        val bottom = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(10, 8, 10, 10)
            setBackgroundColor(Color.WHITE)
            elevation = 12f
        }
        saveButton = Button(this).apply {
            text = "СОХРАНИТЬ ОБЪЕКТ В ЭТОЙ ТОЧКЕ"
            isEnabled = false
        }
        listButton = Button(this).apply {
            text = "СОХРАНЁННЫЕ ОБЪЕКТЫ (" + objects.length() + ")"
        }
        val backButton = Button(this).apply { text = "НАЗАД" }
        bottom.addView(saveButton, LinearLayout.LayoutParams(-1, -2))
        bottom.addView(listButton, LinearLayout.LayoutParams(-1, -2))
        bottom.addView(backButton, LinearLayout.LayoutParams(-1, -2))
        root.addView(bottom, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM))
        setContentView(root)

        saveButton.setOnClickListener { saveCurrentPoint() }
        listButton.setOnClickListener { showObjects() }
        backButton.setOnClickListener { finish() }

        mapView.onCreate(savedInstanceState)
        mapView.getMapAsync { mapInstance ->
            map = mapInstance
            map.cameraPosition = CameraPosition.Builder()
                .target(LatLng(42.3417, 69.5901))
                .zoom(15.0)
                .build()
            map.uiSettings.isLogoEnabled = false
            map.setStyle(Style.Builder().fromUri(MapEngineManager.STYLE_URL)) {
                saveButton.isEnabled = true
                status.text = "Карта готова. Совместите место с прицелом."
            }
            map.addOnCameraIdleListener idleListener@{
                val p = map.cameraPosition.target ?: return@idleListener
                status.text = String.format(
                    java.util.Locale.US,
                    "Координаты прицела: %.6f, %.6f",
                    p.latitude, p.longitude
                )
            }
        }
    }

    private fun loadObjects() {
        try {
            val saved = JSONArray(prefs.getString("items", "[]") ?: "[]")
            for (i in 0 until saved.length()) objects.put(saved.getJSONObject(i))
        } catch (_: Exception) { }
    }

    private fun saveCurrentPoint() {
        if (!::map.isInitialized) return
        val point = map.cameraPosition.target ?: return
        val latitude = point.latitude
        val longitude = point.longitude
        val item = JSONObject().apply {
            put("category", categories[category.selectedItemPosition])
            put("latitude", latitude)
            put("longitude", longitude)
            put("created_at", System.currentTimeMillis())
        }
        objects.put(item)
        prefs.edit().putString("items", objects.toString()).apply()
        listButton.text = "СОХРАНЁННЫЕ ОБЪЕКТЫ (" + objects.length() + ")"
        Toast.makeText(this, "Объект сохранён на устройстве", Toast.LENGTH_SHORT).show()
    }

    private fun showObjects() {
        if (objects.length() == 0) {
            AlertDialog.Builder(this).setMessage("Сохранённых объектов пока нет")
                .setPositiveButton("OK", null).show()
            return
        }
        val rows = Array(objects.length()) { i ->
            val item = objects.getJSONObject(i)
            String.format(
                java.util.Locale.US, "%d. %s\n%.6f, %.6f",
                i + 1, item.optString("category"),
                item.optDouble("latitude"), item.optDouble("longitude")
            )
        }
        AlertDialog.Builder(this).setTitle("Объекты на устройстве")
            .setItems(rows, null)
            .setPositiveButton("Закрыть", null)
            .show()
    }

    override fun onStart() { super.onStart(); mapView.onStart() }
    override fun onResume() { super.onResume(); mapView.onResume() }
    override fun onPause() { mapView.onPause(); super.onPause() }
    override fun onStop() { mapView.onStop(); super.onStop() }
    override fun onLowMemory() { super.onLowMemory(); mapView.onLowMemory() }
    override fun onDestroy() { mapView.onDestroy(); super.onDestroy() }
    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        mapView.onSaveInstanceState(outState)
    }
}