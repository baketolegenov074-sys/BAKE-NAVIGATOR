package kz.bake.navigator

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.maplibre.android.geometry.LatLng
import org.maplibre.geojson.Point
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class RouteAndSearchManager {
    data class Place(val label: String, val lat: Double, val lon: Double)
    data class NavigationStep(
        val instruction: String,
        val instructionKazakh: String,
        val latitude: Double,
        val longitude: Double,
        val distanceMeters: Double,
        val maneuverType: String
    )
    data class RouteResult(
        val points: List<Point>,
        val distanceMeters: Double,
        val durationSeconds: Double,
        val steps: List<NavigationStep>
    )

    private val http = OkHttpClient.Builder()
        .connectTimeout(12, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .build()

    fun search(query: String): List<Place> = try {
        val encoded = URLEncoder.encode(query, "UTF-8")
        val url = "https://photon.komoot.io/api/?q=$encoded&lat=42.3417&lon=69.5901&limit=7"
        http.newCall(Request.Builder().url(url).header("User-Agent", "BAKE-Navigator/1.0").build()).execute().use { response ->
            if (!response.isSuccessful) return emptyList()
            val features = JSONObject(response.body?.string() ?: return emptyList()).optJSONArray("features") ?: return emptyList()
            buildList {
                for (i in 0 until features.length()) {
                    val feature = features.optJSONObject(i) ?: continue
                    val coords = feature.optJSONObject("geometry")?.optJSONArray("coordinates") ?: continue
                    if (coords.length() < 2) continue
                    val props = feature.optJSONObject("properties") ?: JSONObject()
                    val parts = listOf(props.optString("name"), props.optString("street"), props.optString("housenumber"), props.optString("city"), props.optString("district"))
                        .filter { it.isNotBlank() && it != "null" }.distinct()
                    add(Place(parts.joinToString(", ").ifBlank { query }, coords.getDouble(1), coords.getDouble(0)))
                }
            }
        }
    } catch (_: Exception) { emptyList() }

    fun buildRoutes(start: LatLng, end: LatLng): List<RouteResult> {
        val url = "https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?alternatives=true&steps=true&overview=full&geometries=geojson"
        return http.newCall(Request.Builder().url(url).header("User-Agent", "BAKE-Navigator/1.0").build()).execute().use { response ->
            if (!response.isSuccessful) error("OSRM HTTP ${response.code}")
            val root = JSONObject(response.body?.string() ?: error("Пустой ответ OSRM"))
            if (root.optString("code") != "Ok") error(root.optString("message", "Маршрут не найден"))
            val routes = root.optJSONArray("routes") ?: error("OSRM не вернул маршруты")
            buildList {
                for (i in 0 until minOf(routes.length(), 3)) {
                    val route = routes.optJSONObject(i) ?: continue
                    val coords = route.getJSONObject("geometry").getJSONArray("coordinates")
                    val points = ArrayList<Point>(coords.length())
                    for (j in 0 until coords.length()) {
                        val pair = coords.getJSONArray(j)
                        points.add(Point.fromLngLat(pair.getDouble(0), pair.getDouble(1)))
                    }
                    val steps = ArrayList<NavigationStep>()
                    val legs = route.optJSONArray("legs")
                    if (legs != null) for (legIndex in 0 until legs.length()) {
                        val leg = legs.optJSONObject(legIndex) ?: continue
                        val legSteps = leg.optJSONArray("steps") ?: continue
                        for (stepIndex in 0 until legSteps.length()) {
                            val step = legSteps.optJSONObject(stepIndex) ?: continue
                            val maneuver = step.optJSONObject("maneuver") ?: continue
                            val location = maneuver.optJSONArray("location") ?: continue
                            if (location.length() < 2) continue
                            val type = maneuver.optString("type")
                            val modifier = maneuver.optString("modifier")
                            val name = step.optString("name").takeUnless { it == "null" }.orEmpty()
                            steps.add(
                                NavigationStep(
                                    instruction = makeInstruction(type, modifier, name, maneuver.optInt("exit", -1)),
                                    instructionKazakh = makeInstructionKazakh(type, modifier, name, maneuver.optInt("exit", -1)),
                                    latitude = location.getDouble(1),
                                    longitude = location.getDouble(0),
                                    distanceMeters = step.optDouble("distance", 0.0),
                                    maneuverType = type
                                )
                            )
                        }
                    }
                    add(RouteResult(points, route.optDouble("distance", 0.0), route.optDouble("duration", 0.0), steps))
                }
            }
        }
    }


    fun fetchSpeedLimit(latitude: Double, longitude: Double): Int? = try {
        val query = "[out:json][timeout:10];way(around:25,$latitude,$longitude)[\"highway\"][\"maxspeed\"];out geom;"
        val body = "data=" + URLEncoder.encode(query, "UTF-8")
        http.newCall(
            Request.Builder()
                .url("https://overpass-api.de/api/interpreter")
                .post(body.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
                .header("User-Agent", "BAKE-Navigator/1.0")
                .build()
        ).execute().use { response ->
            if (!response.isSuccessful) return null
            val elements = JSONObject(response.body?.string() ?: return null).optJSONArray("elements") ?: return null
            var nearestDistance = Double.MAX_VALUE
            var nearestLimit: Int? = null
            val scaleY = 111320.0
            val scaleX = scaleY * kotlin.math.cos(Math.toRadians(latitude))
            for (i in 0 until elements.length()) {
                val item = elements.optJSONObject(i) ?: continue
                val tags = item.optJSONObject("tags") ?: continue
                val rawLimit = tags.optString("maxspeed").trim()
                val number = Regex("\\d+(?:\\.\\d+)?").find(rawLimit)?.value?.toDoubleOrNull() ?: continue
                val limit = if (rawLimit.contains("mph", true)) (number * 1.60934).toInt() else number.toInt()
                val geometry = item.optJSONArray("geometry") ?: continue
                for (j in 0 until geometry.length() - 1) {
                    val a = geometry.optJSONObject(j) ?: continue
                    val b = geometry.optJSONObject(j + 1) ?: continue
                    val ax = (a.optDouble("lon") - longitude) * scaleX
                    val ay = (a.optDouble("lat") - latitude) * scaleY
                    val bx = (b.optDouble("lon") - longitude) * scaleX
                    val by = (b.optDouble("lat") - latitude) * scaleY
                    val dx = bx - ax
                    val dy = by - ay
                    val denominator = dx * dx + dy * dy
                    val t = if (denominator == 0.0) 0.0 else (-(ax * dx + ay * dy) / denominator).coerceIn(0.0, 1.0)
                    val distance = kotlin.math.hypot(ax + t * dx, ay + t * dy)
                    if (distance < nearestDistance) {
                        nearestDistance = distance
                        nearestLimit = limit
                    }
                }
            }
            if (nearestDistance <= 20.0) nearestLimit else null
        }
    } catch (_: Exception) { null }

 
    private fun makeInstructionKazakh(type: String, modifier: String, road: String, exit: Int): String {
        val direction = when (modifier) {
            "left", "slight left", "sharp left" -> "солға"
            "right", "slight right", "sharp right" -> "оңға"
            "straight" -> "тура"
            "uturn" -> "кері"
            else -> ""
        }
        val action = when (type) {
            "depart" -> "Қозғалысты бастаңыз"
            "arrive" -> "Межелі жерге жеттіңіз"
            "turn", "end of road" -> if (direction.isNotEmpty()) "$direction бұрылыңыз" else "Тура жүре беріңіз"
            "new name", "continue" -> "Тура жүре беріңіз"
            "merge" -> "Қатарға ауысыңыз"
            "on ramp" -> "Кіру жолына бұрылыңыз"
            "off ramp" -> "Жолдан шығыңыз"
            "fork" -> if (direction.isNotEmpty()) "Айрықта $direction бағытты ұстаныңыз" else "Айрықта тура жүріңіз"
            "roundabout", "rotary" -> if (exit > 0) "Айналма жолда $exit-ші шығаберісті пайдаланыңыз" else "Айналма жолға кіріңіз"
            "exit roundabout", "exit rotary" -> "Айналма жолдан шығыңыз"
            else -> if (direction.isNotEmpty()) "$direction жүріңіз" else "Тура жүре беріңіз"
        }
        return if (road.isNotBlank() && type != "arrive" && type != "depart") "$action, $road көшесімен" else action
    }

    private fun makeInstruction(type: String, modifier: String, road: String, exit: Int): String {
        val direction = when (modifier) {
            "left", "slight left", "sharp left" -> "налево"
            "right", "slight right", "sharp right" -> "направо"
            "straight" -> "прямо"
            "uturn" -> "развернитесь"
            else -> ""
        }
        val action = when (type) {
            "depart" -> "Начинайте движение"
            "arrive" -> "Вы прибыли в пункт назначения"
            "turn", "end of road" -> if (direction.isNotEmpty()) "Поверните $direction" else "Продолжайте движение"
            "new name", "continue" -> "Продолжайте движение"
            "merge" -> "Перестройтесь"
            "on ramp" -> "Съезжайте на въезд"
            "off ramp" -> "Съезжайте с дороги"
            "fork" -> if (direction.isNotEmpty()) "На развилке держитесь $direction" else "На развилке продолжайте движение"
            "roundabout", "rotary" -> if (exit > 0) "На круговом движении используйте $exit-й съезд" else "Въезжайте на круговое движение"
            "exit roundabout", "exit rotary" -> "Съезжайте с кругового движения"
            else -> if (direction.isNotEmpty()) "Двигайтесь $direction" else "Продолжайте движение"
        }
        return if (road.isNotBlank() && type != "arrive" && type != "depart") "$action на $road" else action
    }
}