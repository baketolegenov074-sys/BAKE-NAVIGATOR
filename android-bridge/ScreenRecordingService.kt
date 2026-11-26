package kz.bake.bake_navigator

import android.app.*
import android.content.*
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenRecordingService : Service() {
 companion object {
  const val ACTION_START="kz.bake.bake_navigator.action.START_SCREEN_RECORDING"; const val ACTION_STOP="kz.bake.bake_navigator.action.STOP_SCREEN_RECORDING"; const val ACTION_STOPPED="kz.bake.bake_navigator.action.SCREEN_RECORDING_STOPPED"
  const val EXTRA_RESULT_CODE="projection_result_code"; const val EXTRA_RESULT_DATA="projection_result_data"; const val EXTRA_PATH="recording_path"
  private const val PREFS="bake_screen_recording"; private const val CHANNEL="bake_screen_recording"; private const val ID=7402
  fun isRecording(c:Context)=c.getSharedPreferences(PREFS,0).getBoolean("active",false)
  fun lastPath(c:Context)=c.getSharedPreferences(PREFS,0).getString("last_file",null)
  fun list(c:Context):ArrayList<HashMap<String,Any>> { val dir=File(c.getExternalFilesDir(Environment.DIRECTORY_MOVIES),"BAKE-Diagnostics"); val fs=dir.listFiles()?.filter{it.isFile&&it.extension.equals("mp4",true)}?.sortedByDescending{it.lastModified()}?:emptyList(); return ArrayList(fs.map{hashMapOf("path" to it.absolutePath,"name" to it.name,"size" to it.length(),"modified" to it.lastModified()/1000L)}) }
 }
 private var projection:MediaProjection?=null; private var recorder:MediaRecorder?=null; private var display:VirtualDisplay?=null; private var output:File?=null; private var stopping=false
 override fun onBind(intent:Intent?):IBinder?=null
 override fun onCreate(){super.onCreate();event("service_created")}
 override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int { when(intent?.action){ ACTION_STOP->stopRecording("user_stop"); ACTION_START->{ if(recorder!=null)return START_NOT_STICKY; val code=intent.getIntExtra(EXTRA_RESULT_CODE,0); val data=if(Build.VERSION.SDK_INT>=33)intent.getParcelableExtra(EXTRA_RESULT_DATA,Intent::class.java) else @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_RESULT_DATA); if(data==null){errorState("missing_projection_data");stopSelf();return START_NOT_STICKY}; startForegroundNow(); try{begin(code,data)}catch(e:Exception){errorState("start_failed: "+e.javaClass.simpleName+": "+e.message);stopRecording("start_failed")} } }; return START_NOT_STICKY }
 private fun event(s:String){getSharedPreferences(PREFS,0).edit().putString("last_event",System.currentTimeMillis().toString()+":"+s).apply()}
 private fun errorState(s:String){getSharedPreferences(PREFS,0).edit().putString("last_error",s).putString("last_event",System.currentTimeMillis().toString()+":"+s).apply()}
 private fun startForegroundNow(){val nm=getSystemService(NotificationManager::class.java);if(Build.VERSION.SDK_INT>=26)nm.createNotificationChannel(NotificationChannel(CHANNEL,"Запись экрана BAKE",NotificationManager.IMPORTANCE_LOW));val stop=PendingIntent.getService(this,7403,Intent(this,ScreenRecordingService::class.java).setAction(ACTION_STOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);val b=if(Build.VERSION.SDK_INT>=26)Notification.Builder(this,CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this);val n=b.setSmallIcon(android.R.drawable.ic_menu_camera).setContentTitle("BAKE Navigator").setContentText("Идёт запись экрана для диагностики").setOngoing(true).setCategory(Notification.CATEGORY_SERVICE).addAction(android.R.drawable.ic_media_pause,"Остановить",stop).build();if(Build.VERSION.SDK_INT>=29)startForeground(ID,n,android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)else startForeground(ID,n)}
 private fun begin(code:Int,data:Intent){val pm=getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager;projection=pm.getMediaProjection(code,data)?:error("MediaProjection недоступен");projection!!.registerCallback(object:MediaProjection.Callback(){override fun onStop(){if(!stopping)stopRecording("android_projection_stopped")}},Handler(Looper.getMainLooper()));val m=DisplayMetrics();@Suppress("DEPRECATION") (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(m);val w=(m.widthPixels/2)*2;val h=(m.heightPixels/2)*2;val dir=File(getExternalFilesDir(Environment.DIRECTORY_MOVIES),"BAKE-Diagnostics");if(!dir.exists()&&!dir.mkdirs())error("Не удалось создать папку записи");output=File(dir,"bake_screen_"+SimpleDateFormat("yyyyMMdd_HHmmss",Locale.US).format(Date())+".mp4");val mr=if(Build.VERSION.SDK_INT>=31)MediaRecorder(this)else @Suppress("DEPRECATION") MediaRecorder();recorder=mr;mr.setVideoSource(MediaRecorder.VideoSource.SURFACE);mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);mr.setVideoEncoder(MediaRecorder.VideoEncoder.H264);mr.setVideoSize(w,h);mr.setVideoFrameRate(30);mr.setVideoEncodingBitRate(6000000);mr.setOutputFile(output!!.absolutePath);mr.prepare();display=projection!!.createVirtualDisplay("BAKE diagnostics",w,h,m.densityDpi,DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,mr.surface,null,null);mr.start();getSharedPreferences(PREFS,0).edit().putBoolean("active",true).remove("last_error").putString("last_event",System.currentTimeMillis().toString()+":recording_started").apply()}
 private fun stopRecording(reason:String){if(stopping)return;stopping=true;try{finish(reason)}finally{stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()}}
 private fun finish(reason:String){try{recorder?.let{try{it.stop()}catch(e:RuntimeException){errorState("recorder_stop_failed: "+e.message)};try{it.reset()}catch(_:Exception){};try{it.release()}catch(_:Exception){}};recorder=null;try{display?.release()}catch(_:Exception){};display=null;try{projection?.stop()}catch(_:Exception){};projection=null;val saved=output?.takeIf{it.exists()&&it.length()>1024L};val p=getSharedPreferences(PREFS,0).edit().putBoolean("active",false).putString("last_event",System.currentTimeMillis().toString()+":stopped:"+reason);if(saved!=null)p.putString("last_file",saved.absolutePath);p.apply();sendBroadcast(Intent(ACTION_STOPPED).setPackage(packageName).putExtra(EXTRA_PATH,saved?.absolutePath))}finally{recorder=null}}
 override fun onTaskRemoved(rootIntent:Intent?){event("task_removed_service_kept");super.onTaskRemoved(rootIntent)}
 override fun onDestroy(){if(!stopping&&recorder!=null){event("service_destroyed_finalize_partial");stopping=true;finish("service_destroyed")};super.onDestroy()}
}
