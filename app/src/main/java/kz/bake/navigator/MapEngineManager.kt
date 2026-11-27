package kz.bake.navigator
import android.content.Context
import android.graphics.Color
import android.widget.ImageView
import androidx.lifecycle.LifecycleCoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.style.layers.*
import org.maplibre.android.style.layers.PropertyFactory.*
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.*
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class MapEngineManager(private val context: Context, private val scope: LifecycleCoroutineScope) {
 companion object {
  const val STYLE_URL="https://styles.maptoolkit.org/street.json"
  fun initializeSdk(context:Context){MapLibre.getInstance(context)}
 }
 var map:MapLibreMap?=null;private set
 private val http=OkHttpClient.Builder().connectTimeout(12,TimeUnit.SECONDS).readTimeout(25,TimeUnit.SECONDS).build()
 private var lastPoiLoad=0L
 fun initialize(view:MapView,onLongPress:(LatLng)->Unit,onReady:()->Unit){
  view.getMapAsync{m->
   map=m;m.cameraPosition=CameraPosition.Builder().target(LatLng(42.3417,69.5901)).zoom(14.5).build()
   m.uiSettings.isLogoEnabled=false;m.uiSettings.setAttributionMargins(0,0,12,8)
   m.addOnMapLongClickListener{p->onLongPress(p);true}
   m.addOnCameraIdleListener{loadOsmFeaturesIfNeeded()}
   m.setStyle(Style.Builder().fromUri(STYLE_URL)){s->addLayers(s);onReady()}
  }
 }
 fun updateRealLocation(location:android.location.Location){
  val point=Point.fromLngLat(location.longitude,location.latitude)
  map?.getStyle { style ->
   style.getSourceAs<GeoJsonSource>("gps-position-source")?.setGeoJson(Feature.fromGeometry(point))
  }
 }
 fun setSimulationMarker(point:LatLng){
  map?.getStyle{s->s.getSourceAs<GeoJsonSource>("sim-marker-source")?.setGeoJson(Feature.fromGeometry(Point.fromLngLat(point.longitude,point.latitude)))}
 }
 fun clearSimulationMarker(){
  map?.getStyle{s->s.getSourceAs<GeoJsonSource>("sim-marker-source")?.setGeoJson(FeatureCollection.fromFeatures(emptyArray()))}
 }
 fun setRoute(points:List<Point>){map?.getStyle{s->val src=s.getSourceAs<GeoJsonSource>("route-source");if(points.isEmpty())src?.setGeoJson(FeatureCollection.fromFeatures(emptyArray()))else src?.setGeoJson(LineString.fromLngLats(points))}}
 fun setDestination(p:LatLng?){map?.getStyle{s->val src=s.getSourceAs<GeoJsonSource>("destination-source");if(p==null)src?.setGeoJson(FeatureCollection.fromFeatures(emptyArray()))else src?.setGeoJson(Feature.fromGeometry(Point.fromLngLat(p.longitude,p.latitude)))}}
 fun cameraTo(p:LatLng,zoom:Double=14.5){map?.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(p).zoom(zoom).tilt(0.0).bearing(0.0).build()),500)}
 fun follow(p:LatLng,bearing:Double){map?.easeCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder().target(p).zoom(17.0).tilt(50.0).bearing(bearing).build()),250)}
 fun loadLogo(image:ImageView){scope.launch(Dispatchers.IO){try{
  val bytes=http.newCall(Request.Builder().url("https://www.maptoolkit.org/assets/maptoolkit-attribution.png").header("User-Agent","BAKE-Navigator/1.0").build()).execute().use{if(!it.isSuccessful)return@launch;it.body?.bytes()?:return@launch}
  val bitmap=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.size)?:return@launch
  withContext(Dispatchers.Main){image.setImageBitmap(bitmap)}
 }catch(_:Exception){}}}
 private fun addLayers(s:Style){
  s.addSource(GeoJsonSource("route-source"));s.addLayer(LineLayer("route-layer","route-source").withProperties(lineColor(Color.parseColor("#1976D2")),lineWidth(7f),lineCap(Property.LINE_CAP_ROUND),lineJoin(Property.LINE_JOIN_ROUND)))
  s.addSource(GeoJsonSource("destination-source"));s.addLayer(CircleLayer("destination-layer","destination-source").withProperties(circleColor(Color.parseColor("#E53935")),circleRadius(9f),circleStrokeColor(Color.WHITE),circleStrokeWidth(2.5f)))
  s.addSource(GeoJsonSource("gps-position-source"));s.addLayer(CircleLayer("gps-position-layer","gps-position-source").withProperties(circleColor(Color.parseColor("#1976D2")),circleRadius(6f),circleStrokeColor(Color.WHITE),circleStrokeWidth(2.5f)))
  s.addSource(GeoJsonSource("sim-marker-source"));s.addLayer(CircleLayer("sim-marker-layer","sim-marker-source").withProperties(circleColor(Color.parseColor("#FF9800")),circleRadius(8f),circleStrokeColor(Color.WHITE),circleStrokeWidth(2.5f)))
  s.addSource(GeoJsonSource("osm-parking-source"));s.addSource(GeoJsonSource("osm-signals-source"))
  val p=CircleLayer("osm-parking-circles","osm-parking-source").withProperties(circleColor(Color.parseColor("#1565C0")),circleRadius(7f),circleStrokeColor(Color.WHITE),circleStrokeWidth(1.5f));p.setMinZoom(14f);s.addLayer(p)
  val pt=SymbolLayer("osm-parking-labels","osm-parking-source").withProperties(textField("P"),textSize(10f),textColor(Color.WHITE),textIgnorePlacement(true),textAllowOverlap(true));pt.setMinZoom(14f);s.addLayer(pt)
  val l=CircleLayer("osm-signal-circles","osm-signals-source").withProperties(circleColor(Color.parseColor("#D32F2F")),circleRadius(6f),circleStrokeColor(Color.WHITE),circleStrokeWidth(1.5f));l.setMinZoom(14f);s.addLayer(l)
  val lt=SymbolLayer("osm-signal-labels","osm-signals-source").withProperties(textField("●"),textSize(10f),textColor(Color.WHITE),textIgnorePlacement(true),textAllowOverlap(true));lt.setMinZoom(14f);s.addLayer(lt)
 }
 private fun loadOsmFeaturesIfNeeded(){
  val m=map?:return;if(m.cameraPosition.zoom<13.0||System.currentTimeMillis()-lastPoiLoad<60_000L)return
  val b=m.projection.visibleRegion.latLngBounds;val south=b.latitudeSouth;val west=b.longitudeWest;val north=b.latitudeNorth;val east=b.longitudeEast;lastPoiLoad=System.currentTimeMillis()
  scope.launch(Dispatchers.IO){try{
   val q="[out:json][timeout:20];(node[\"amenity\"=\"parking\"]($south,$west,$north,$east);way[\"amenity\"=\"parking\"]($south,$west,$north,$east);node[\"highway\"=\"traffic_signals\"]($south,$west,$north,$east););out center;"
   val body="data="+URLEncoder.encode(q,"UTF-8")
   http.newCall(Request.Builder().url("https://overpass-api.de/api/interpreter").post(body.toRequestBody("application/x-www-form-urlencoded".toMediaType())).header("User-Agent","BAKE-Navigator/1.0").build()).execute().use{r->
    if(!r.isSuccessful)error("Overpass HTTP ${r.code}")
    val arr=JSONObject(r.body?.string()?:"{}").optJSONArray("elements")?:return@use
    val parking=ArrayList<Feature>();val lights=ArrayList<Feature>()
    for(i in 0 until arr.length()){val item=arr.optJSONObject(i)?:continue;val tags=item.optJSONObject("tags")?:JSONObject();val c=item.optJSONObject("center")
     val lat=if(item.has("lat"))item.optDouble("lat")else c?.optDouble("lat")?:continue
     val lon=if(item.has("lon"))item.optDouble("lon")else c?.optDouble("lon")?:continue
     val f=Feature.fromGeometry(Point.fromLngLat(lon,lat));if(tags.optString("amenity")=="parking")parking.add(f);if(tags.optString("highway")=="traffic_signals")lights.add(f)
    }
    withContext(Dispatchers.Main){map?.getStyle{s->s.getSourceAs<GeoJsonSource>("osm-parking-source")?.setGeoJson(FeatureCollection.fromFeatures(parking));s.getSourceAs<GeoJsonSource>("osm-signals-source")?.setGeoJson(FeatureCollection.fromFeatures(lights))}}
   }
  }catch(_:Exception){}}
 }
}