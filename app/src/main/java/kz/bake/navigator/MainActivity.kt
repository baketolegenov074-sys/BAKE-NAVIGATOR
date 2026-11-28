package kz.bake.navigator

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.location.Location
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapView
import org.maplibre.geojson.Point
import java.util.Locale

class MainActivity : AppCompatActivity() {
 private lateinit var mapView:MapView
 private lateinit var searchInput:EditText
 private lateinit var suggestions:ListView
 private lateinit var routeCard:LinearLayout
 private lateinit var routeInfo:TextView
 private lateinit var goButton:Button
 private lateinit var debugText:TextView
 private lateinit var speedText:TextView
 private lateinit var routeOptionsView:LinearLayout
 private lateinit var voiceLanguageButton:Button
 private lateinit var mapEngine:MapEngineManager
 private lateinit var routeSimulation:RouteSimulationManager
 private lateinit var voice:NavigationVoiceHelper
 private val routes=RouteAndSearchManager()
 private val roadSnapEngine=RoadSnapEngine()
 private var lastRoadRefreshRequestedAt=0L
 private var roadRefreshJob:Job?=null
 private var alternatives:List<RouteAndSearchManager.RouteResult> = emptyList()
 private var activeSteps:List<RouteAndSearchManager.NavigationStep> = emptyList()
 private var selectedRouteIndex=0
 private var nextStepIndex=0
 private var announcedStepIndex=-1
 private var offRouteFixes=0
 private var lastRerouteAt=0L
 private var destination:LatLng?=null
 private var voiceLanguage="ru"
 private var speedLimitKmh:Int?=null
 private var lastSpeedLimitLookupAt=0L
 private var lastOverspeedAnnouncementAt=0L
 private var current=LatLng(42.3417,69.5901)
 private var realGpsLatLng:LatLng?=null
 private var hasCenteredOnGpsFix=false
 private var currentLocation:Location?=null
 private var pendingDestination:LatLng?=null
 private var routePoints:List<Point> = emptyList()
 private var navigating=false
 private var loadingRoute=false
 private var searchJob:Job?=null
 private var lastStatus="Загрузка карты"

 private val permissionLauncher=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()){ result ->
  setStatus("GPS отключён в тестовой карте")
 }

 override fun onCreate(savedInstanceState:Bundle?){
  super.onCreate(savedInstanceState)
  WindowCompat.setDecorFitsSystemWindows(window,true)
  window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
  MapEngineManager.initializeSdk(this)
  setContentView(R.layout.activity_main)
  mapView=findViewById(R.id.mapView);searchInput=findViewById(R.id.searchInput);suggestions=findViewById(R.id.suggestions)
  routeCard=findViewById(R.id.routeCard);routeInfo=findViewById(R.id.routeInfo);goButton=findViewById(R.id.btnGo);debugText=findViewById(R.id.tvDebug)
  speedText=findViewById(R.id.tvSpeed);routeOptionsView=findViewById(R.id.routeOptions);voiceLanguageButton=findViewById(R.id.btnVoiceLanguage)
  mapView.onCreate(savedInstanceState)
  mapEngine=MapEngineManager(this,lifecycleScope);routeSimulation=RouteSimulationManager(lifecycleScope);voice=NavigationVoiceHelper(this)
  mapEngine.loadLogo(findViewById(R.id.maptoolkitLogo))
  findViewById<View>(R.id.maptoolkitLogo).setOnClickListener{openCredit("https://maptoolkit.com/copyright")}
  findViewById<View>(R.id.maptoolkitCredit).setOnClickListener{openCredit("https://maptoolkit.com/copyright")}
  findViewById<View>(R.id.osmCredit).setOnClickListener{openCredit("https://www.openstreetmap.org/copyright")}
  setupSearch();setupControls()
  mapEngine.initialize(mapView,{p->hideKeyboard();searchInput.clearFocus();requestRoute(p)},{setStatus("Карта готова · GPS отключён")})
 }
 private fun openCredit(url:String){startActivity(Intent(Intent.ACTION_VIEW,android.net.Uri.parse(url)))}

 private fun setupSearch(){
  searchInput.setOnEditorActionListener{_,_,_->hideKeyboard();true}
  searchInput.addTextChangedListener(object:android.text.TextWatcher{
   override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int)=Unit
   override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int){
    val q=s?.toString()?.trim().orEmpty();searchJob?.cancel()
    if(q.length<3){suggestions.visibility=View.GONE;return}
    searchJob=lifecycleScope.launch{delay(300);val found=withContext(Dispatchers.IO){routes.search(q)};if(searchInput.text.toString().trim()==q)showSuggestions(found)}
   }
   override fun afterTextChanged(s:android.text.Editable?)=Unit
  })
  findViewById<Button>(R.id.btnSearchClear).apply{contentDescription="Очистить поиск";setOnClickListener{searchInput.text.clear();suggestions.visibility=View.GONE}}
  suggestions.setOnItemClickListener{_,_,index,_->
   val place=suggestions.adapter.getItem(index) as RouteAndSearchManager.Place
   suggestions.visibility=View.GONE;hideKeyboard();searchInput.setText(place.label);searchInput.clearFocus();requestRoute(LatLng(place.lat,place.lon))
  }
 }
 private fun showSuggestions(items:List<RouteAndSearchManager.Place>){
  if(items.isEmpty()){suggestions.visibility=View.GONE;return}
  suggestions.adapter=object:ArrayAdapter<RouteAndSearchManager.Place>(this,android.R.layout.simple_list_item_1,items){
   override fun getView(position:Int,convertView:View?,parent:android.view.ViewGroup):View{
    val v=super.getView(position,convertView,parent) as TextView;v.text=getItem(position)?.label;v.setTextColor(Color.BLACK);v.textSize=14f;v.setPadding(20,16,20,16);v.maxLines=2;return v
   }
  };suggestions.visibility=View.VISIBLE
 }

 private fun setupControls(){
  findViewById<Button>(R.id.btnAdmin).setOnClickListener{startActivity(Intent(this,AdminActivity::class.java))}
  findViewById<Button>(R.id.btnZoomIn).setOnClickListener{mapEngine.map?.animateCamera(CameraUpdateFactory.zoomIn())}
  findViewById<Button>(R.id.btnZoomOut).setOnClickListener{mapEngine.map?.animateCamera(CameraUpdateFactory.zoomOut())}
  findViewById<Button>(R.id.btnMyLocation).visibility=View.GONE
  goButton.setOnClickListener{if(!loadingRoute&&routePoints.isNotEmpty()){if(navigating)stopNavigation()else startNavigation()}}
  findViewById<Button>(R.id.btnReset).setOnClickListener{resetRoute()}
  voiceLanguageButton.setOnClickListener{
   val next=if(voiceLanguage=="ru")"kk" else "ru"
   if(voice.setLanguage(next)){voiceLanguage=next;voiceLanguageButton.text=next.uppercase(Locale.ROOT);setStatus(if(next=="kk")"Голос: казахский" else "Голос: русский")}
   else Toast.makeText(this,if(next=="kk")"Казахский голос недоступен в системном TTS" else "Русский голос недоступен",Toast.LENGTH_LONG).show()
  }
  findViewById<Button>(R.id.btnSimulate).setOnClickListener{
   if(routePoints.isEmpty())Toast.makeText(this,"Сначала выберите адрес или удерживайте карту",Toast.LENGTH_LONG).show()
   else if(navigating)stopNavigation()else{startNavigation();startSimulation()}
  }
 }

 private fun requestRoute(end:LatLng){
  if(loadingRoute)return
  destination=end;mapEngine.setDestination(end)
  pendingDestination=null;loadingRoute=true;setStatus("Ищем варианты маршрута…")
  lifecycleScope.launch{
   try{
    val routeStart=mapEngine.map?.cameraPosition?.target?:current
    val found=withContext(Dispatchers.IO){routes.buildRoutes(routeStart,end)}
    if(found.isEmpty())error("Маршрут не найден")
    alternatives=found;selectedRouteIndex=0;applyRoute(0,false)
    mapEngine.cameraTo(end,14.5);setStatus(if(found.size>1)"Доступно маршрутов: ${found.size}" else "Маршрут построен")
   }catch(e:Exception){setStatus("Ошибка маршрута: ${e.message?:"нет ответа"}");Toast.makeText(this@MainActivity,lastStatus,Toast.LENGTH_LONG).show()}
   finally{loadingRoute=false}
  }
 }
 private fun applyRoute(index:Int,keepNavigation:Boolean){
  val result=alternatives.getOrNull(index)?:return
  selectedRouteIndex=index;routePoints=result.points;activeSteps=result.steps
  nextStepIndex=if(activeSteps.firstOrNull()?.maneuverType=="depart")1 else 0
  announcedStepIndex=-1;offRouteFixes=0
  mapEngine.setRoute(routePoints)
  routeInfo.text=String.format(Locale.getDefault(),"%.1f км  ·  %d мин",result.distanceMeters/1000.0,(result.durationSeconds/60.0).toInt().coerceAtLeast(1))
  renderRouteOptions()
  routeCard.visibility=View.VISIBLE
  if(!keepNavigation){navigating=false;routeSimulation.stopSimulation();restoreRealGpsPosition();goButton.text="ПОЕХАЛИ";goButton.setBackgroundColor(Color.rgb(46,125,50))}
  else{navigating=true;goButton.text="ЗАВЕРШИТЬ";goButton.setBackgroundColor(Color.rgb(239,124,0))}
 }
 private fun renderRouteOptions(){
  routeOptionsView.removeAllViews()
  for(i in alternatives.indices){
   val item=alternatives[i]
   val button=Button(this)
   button.text=String.format(Locale.getDefault(),"Вариант %d\n%.1f км · %d мин",i+1,item.distanceMeters/1000.0,(item.durationSeconds/60.0).toInt().coerceAtLeast(1))
   button.isAllCaps=false;button.textSize=11f;button.minWidth=0;button.setPadding(12,4,12,4)
   button.setBackgroundColor(if(i==selectedRouteIndex)Color.rgb(25,118,210)else Color.LTGRAY)
   button.setTextColor(if(i==selectedRouteIndex)Color.WHITE else Color.DKGRAY)
   button.setOnClickListener{if(!navigating&&!loadingRoute)applyRoute(i,false)}
   val params=LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT,LinearLayout.LayoutParams.WRAP_CONTENT)
   params.marginEnd=8;routeOptionsView.addView(button,params)
  }
  routeOptionsView.visibility=if(alternatives.size>1)View.VISIBLE else View.GONE
 }
 private fun maybeReroute(location:Location,point:LatLng){
  val end=destination?:return
  if(!navigating||loadingRoute||routePoints.size<2)return
  if(location.accuracy>20f){offRouteFixes=0;return}
  val deviation=routeSimulation.distanceToRouteMeters(point,routePoints)
  if(deviation>40.0)offRouteFixes++ else{offRouteFixes=0;return}
  val now=System.currentTimeMillis()
  if(offRouteFixes<3||now-lastRerouteAt<15000L)return
  offRouteFixes=0;lastRerouteAt=now;loadingRoute=true
  setStatus("Отклонение от маршрута: ${deviation.toInt()} м. Перестраиваем…")
  lifecycleScope.launch{
   try{
    val found=withContext(Dispatchers.IO){routes.buildRoutes(point,end)}
    if(found.isEmpty())error("Новый маршрут не найден")
    alternatives=found;applyRoute(0,true);setStatus("Маршрут перестроен")
   }catch(e:Exception){setStatus("Перестроение не удалось; старый маршрут сохранён")}
   finally{loadingRoute=false}
  }
 }
 private fun refreshSpeedLimit(location:Location){
  val now=System.currentTimeMillis()
  if(location.accuracy>15f||now-lastSpeedLimitLookupAt<30000L)return
  lastSpeedLimitLookupAt=now
  speedLimitKmh=null
  lifecycleScope.launch{
   val limit=withContext(Dispatchers.IO){routes.fetchSpeedLimit(location.latitude,location.longitude)}
   speedLimitKmh=limit
  }
 }
 private fun updateVoiceGuidance(point:LatLng){
  while(nextStepIndex<activeSteps.size){
   val step=activeSteps[nextStepIndex]
   val results=FloatArray(1)
   Location.distanceBetween(point.latitude,point.longitude,step.latitude,step.longitude,results)
   val distance=results[0]
   if(distance<=300f&&announcedStepIndex!=nextStepIndex){
    val rounded=(distance/50f).toInt()*50
    val instruction=if(voiceLanguage=="kk")step.instructionKazakh else step.instruction
    voice.speak(if(rounded>0)"Через $rounded метров: $instruction" else instruction)
    announcedStepIndex=nextStepIndex
   }
   if(distance<=35f){nextStepIndex++;continue}
   break
  }
 }
 private fun startNavigation(){
  if(routePoints.isEmpty())return
  navigating=true;goButton.text="ЗАВЕРШИТЬ";goButton.setBackgroundColor(Color.rgb(239,124,0))
  mapEngine.follow(current,currentLocation?.bearing?.toDouble()?:mapEngine.map?.cameraPosition?.bearing?:0.0);setStatus("Ведение маршрута включено")
 }
 private fun stopNavigation(){
  navigating=false;routeSimulation.stopSimulation();goButton.text="ПОЕХАЛИ";goButton.setBackgroundColor(Color.rgb(46,125,50));restoreRealGpsPosition();setStatus("Ведение остановлено; маршрут сохранён")
 }
 private fun resetRoute(){
  navigating=false;routeSimulation.stopSimulation();restoreRealGpsPosition();loadingRoute=false;pendingDestination=null;destination=null
  routePoints=emptyList();alternatives=emptyList();activeSteps=emptyList();routeOptionsView.removeAllViews();offRouteFixes=0
  routeCard.visibility=View.GONE
  goButton.text="ПОЕХАЛИ";goButton.setBackgroundColor(Color.rgb(46,125,50));mapEngine.setRoute(emptyList());mapEngine.setDestination(null);mapEngine.cameraTo(current);setStatus("Маршрут и финиш удалены")
 }
 private fun startSimulation(){
  setStatus("Тест-драйв")
  routeSimulation.startSimulation(routePoints,{p,b->mapEngine.setSimulationMarker(p);current=p;mapEngine.follow(p,b)},{restoreRealGpsPosition();if(navigating)setStatus("Тест-драйв завершён")})
 }
 private fun restoreRealGpsPosition(){
  mapEngine.clearSimulationMarker()
  val real=realGpsLatLng?:currentLocation?.let{LatLng(it.latitude,it.longitude)}?:return
  current=real
  mapEngine.cameraTo(real,if(navigating)17.0 else 16.0)
 }
 private fun startGps(){
  locationManager.start({loc,p->
   realGpsLatLng=p
   currentLocation=loc
   current=p
   // The standalone map must center on its first live GPS fix, not its old Shymkent placeholder.
   if(!hasCenteredOnGpsFix){
    hasCenteredOnGpsFix=true
    mapEngine.cameraTo(p,16.0)
   }
   // Snap only the map marker; raw GPS remains untouched for all navigation logic.
   mapEngine.updateRealLocation(loc,roadSnapEngine.snap(loc)?:p)
   val now=System.currentTimeMillis()
   if(now-lastRoadRefreshRequestedAt>=10_000L&&roadRefreshJob?.isActive!=true){
    lastRoadRefreshRequestedAt=now
    roadRefreshJob=lifecycleScope.launch{
     withContext(Dispatchers.IO){roadSnapEngine.refreshRoads(loc)}
     val latest=currentLocation
     if(latest!=null){
      val raw=LatLng(latest.latitude,latest.longitude)
      mapEngine.updateRealLocation(latest,roadSnapEngine.snap(latest)?:raw)
     }
    }
   }
   val simulationActive=routeSimulation.isSimulationActive
   val activeNavigation=navigating&&!simulationActive
   // The real GPS puck, camera and navigation state use the same raw Android fix.
   if(!simulationActive)current=p
   if(!simulationActive)pendingDestination?.let{pending->pendingDestination=null;requestRoute(pending)}
   if(activeNavigation){
    maybeReroute(loc,p)
    updateVoiceGuidance(p)
    val b=if(loc.hasBearing())loc.bearing.toDouble()else mapEngine.map?.cameraPosition?.bearing?:0.0
    mapEngine.follow(p,b)
   }
   refreshSpeedLimit(loc)
   val speed=locationManager.speedKmh.coerceAtLeast(0f).toInt()
   val limit=speedLimitKmh
   speedText.text=if(limit!=null)"$speed км/ч\nЛимит $limit" else "$speed км/ч\nЛимит —"
   speedText.setTextColor(if(limit!=null&&speed>limit+5)Color.RED else Color.BLACK)
   if(navigating&&limit!=null&&speed>limit+5&&System.currentTimeMillis()-lastOverspeedAnnouncementAt>30000L){
    lastOverspeedAnnouncementAt=System.currentTimeMillis()
    voice.speak(if(voiceLanguage=="kk")"Назар аударыңыз. Жылдамдық шегі сағатына $limit километр" else "Внимание. Ограничение скорости $limit километров в час")
   }
   debugText.text="GPS ±${loc.accuracy.toInt()} м  ·  ${if(navigating)"Ведение" else "Ожидание"}"
  },::setStatus)
 }
 private fun hideKeyboard(){(getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(searchInput.windowToken,0)}
 private fun setStatus(message:String){lastStatus=message;if(::debugText.isInitialized)debugText.text=message}
 override fun onStart(){super.onStart();mapView.onStart()}
 override fun onResume(){super.onResume();mapView.onResume()}
 private fun hasLocationPermission():Boolean {
  return ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_FINE_LOCATION)==PackageManager.PERMISSION_GRANTED || ContextCompat.checkSelfPermission(this,Manifest.permission.ACCESS_COARSE_LOCATION)==PackageManager.PERMISSION_GRANTED
 }
 override fun onPause(){super.onPause();mapView.onPause()}
 override fun onStop(){super.onStop();mapView.onStop()}
 override fun onLowMemory(){super.onLowMemory();mapView.onLowMemory()}
 override fun onDestroy(){searchJob?.cancel();roadRefreshJob?.cancel();routeSimulation.release();voice.release();mapView.onDestroy();super.onDestroy()}
 override fun onSaveInstanceState(outState:Bundle){super.onSaveInstanceState(outState);mapView.onSaveInstanceState(outState)}
}