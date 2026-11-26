package kz.bake.bake_navigator
import android.app.Activity
import android.content.*
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat
class ScreenRecordingBridge(private val activity:Activity,messenger:BinaryMessenger,private val appContext:Context):MethodChannel.MethodCallHandler{
 companion object{private const val CHANNEL="bake.navigator/screen_recording";private const val REQUEST_CAPTURE=7401}
 private val channel=MethodChannel(messenger,CHANNEL);private val handler=Handler(Looper.getMainLooper());private var pendingStart:MethodChannel.Result?=null;private var pendingStop:MethodChannel.Result?=null
 private val receiver=object:BroadcastReceiver(){override fun onReceive(context:Context?,intent:Intent?){pendingStop?.success(intent?.getStringExtra(ScreenRecordingService.EXTRA_PATH));pendingStop=null}}
 init{channel.setMethodCallHandler(this);val f=IntentFilter(ScreenRecordingService.ACTION_STOPPED);if(Build.VERSION.SDK_INT>=33)appContext.registerReceiver(receiver,f,Context.RECEIVER_NOT_EXPORTED)else @Suppress("DEPRECATION") appContext.registerReceiver(receiver,f)}
 override fun onMethodCall(call:MethodCall,result:MethodChannel.Result){when(call.method){
 "isRecording"->result.success(ScreenRecordingService.isRecording(appContext))
 "lastRecordingPath"->result.success(ScreenRecordingService.lastPath(appContext))
 "listRecordings"->result.success(ScreenRecordingService.list(appContext))
 "lastRecordingError"->result.success(appContext.getSharedPreferences("bake_screen_recording",0).getString("last_error",null))
 "startRecording"->{if(pendingStart!=null){result.error("BUSY","Запрос разрешения уже открыт",null);return};if(ScreenRecordingService.isRecording(appContext)){result.success(true);return};pendingStart=result;try{val pm=activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager;activity.startActivityForResult(pm.createScreenCaptureIntent(),REQUEST_CAPTURE)}catch(e:Exception){pendingStart=null;result.error("CAPTURE_REQUEST_FAILED",e.message,null)}}
 "stopRecording"->{if(!ScreenRecordingService.isRecording(appContext)){result.success(ScreenRecordingService.lastPath(appContext));return};pendingStop=result;try{ContextCompat.startForegroundService(activity,Intent(activity,ScreenRecordingService::class.java).setAction(ScreenRecordingService.ACTION_STOP));handler.postDelayed({if(pendingStop===result){pendingStop=null;result.success(ScreenRecordingService.lastPath(appContext))}},5000)}catch(e:Exception){pendingStop=null;result.error("STOP_FAILED",e.message,null)}}
 else->result.notImplemented()}}
 fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?):Boolean{if(requestCode!=REQUEST_CAPTURE)return false;val cb=pendingStart;pendingStart=null;if(cb==null)return true;if(resultCode!=Activity.RESULT_OK||data==null){cb.error("CAPTURE_DENIED","Разрешение на запись экрана не выдано",null);return true};try{val i=Intent(activity,ScreenRecordingService::class.java).setAction(ScreenRecordingService.ACTION_START).putExtra(ScreenRecordingService.EXTRA_RESULT_CODE,resultCode).putExtra(ScreenRecordingService.EXTRA_RESULT_DATA,data);ContextCompat.startForegroundService(activity,i);cb.success(true)}catch(e:Exception){cb.error("RECORDING_START_FAILED",e.message,null)};return true}
 fun close(){channel.setMethodCallHandler(null);pendingStart?.error("ACTIVITY_CLOSED","Экран диагностики закрыт",null);pendingStart=null;try{appContext.unregisterReceiver(receiver)}catch(_:Exception){}}
}
