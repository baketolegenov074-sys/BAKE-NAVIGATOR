package kz.bake.bake_navigator

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat

class ScreenRecordingBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val appContext: Context,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "bake.navigator/screen_recording"
        private const val REQUEST_CAPTURE = 7401
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingStart: MethodChannel.Result? = null
    private var pendingStop: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isRecording" -> result.success(ScreenRecordingService.isRecording(appContext))
            "lastRecordingPath" -> result.success(ScreenRecordingService.lastRecordingPath(appContext))
            "startRecording" -> {
                if (pendingStart != null) {
                    result.error("BUSY", "Запрос разрешения уже открыт", null)
                    return
                }
                if (ScreenRecordingService.isRecording(appContext)) {
                    result.success(true)
                    return
                }
                pendingStart = result
                try {
                    val manager = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    activity.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAPTURE)
                } catch (error: Exception) {
                    pendingStart = null
                    result.error("CAPTURE_REQUEST_FAILED", error.message, null)
                }
            }
            "stopRecording" -> {
                if (!ScreenRecordingService.isRecording(appContext)) {
                    result.success(ScreenRecordingService.lastRecordingPath(appContext))
                    return
                }
                pendingStop = result
                ScreenRecordingService.onRecordingStopped = { path ->
                    mainHandler.post {
                        pendingStop?.success(path)
                        pendingStop = null
                        ScreenRecordingService.onRecordingStopped = null
                    }
                }
                try {
                    activity.startService(
                        Intent(activity, ScreenRecordingService::class.java)
                            .setAction(ScreenRecordingService.ACTION_STOP)
                    )
                } catch (error: Exception) {
                    pendingStop = null
                    ScreenRecordingService.onRecordingStopped = null
                    result.error("STOP_FAILED", error.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CAPTURE) return false
        val callback = pendingStart
        pendingStart = null
        if (callback == null) return true
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.error("CAPTURE_DENIED", "Разрешение на запись экрана не выдано", null)
            return true
        }
        try {
            val serviceIntent = Intent(activity, ScreenRecordingService::class.java)
                .setAction(ScreenRecordingService.ACTION_START)
                .putExtra(ScreenRecordingService.EXTRA_RESULT_CODE, resultCode)
                .putExtra(ScreenRecordingService.EXTRA_RESULT_DATA, data)
            ContextCompat.startForegroundService(activity, serviceIntent)
            callback.success(true)
        } catch (error: Exception) {
            callback.error("RECORDING_START_FAILED", error.message, null)
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingStart?.error("ACTIVITY_CLOSED", "Экран диагностики закрыт", null)
        pendingStart = null
    }
}
