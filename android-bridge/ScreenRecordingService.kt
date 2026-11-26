package kz.bake.bake_navigator

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenRecordingService : Service() {
    companion object {
        const val ACTION_START = "kz.bake.bake_navigator.action.START_SCREEN_RECORDING"
        const val ACTION_STOP = "kz.bake.bake_navigator.action.STOP_SCREEN_RECORDING"
        const val EXTRA_RESULT_CODE = "projection_result_code"
        const val EXTRA_RESULT_DATA = "projection_result_data"
        private const val CHANNEL_ID = "bake_screen_recording"
        private const val NOTIFICATION_ID = 7402
        private const val PREFS = "bake_screen_recording"
        private const val KEY_ACTIVE = "active"
        private const val KEY_LAST_FILE = "last_file"

        @Volatile
        var onRecordingStopped: ((String?) -> Unit)? = null

        fun isRecording(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ACTIVE, false)
    }

    private var projection: MediaProjection? = null
    private var recorder: MediaRecorder? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var outputFile: File? = null
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopRecording()
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                if (data == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForegroundCompat()
                try {
                    beginRecording(resultCode, data)
                } catch (error: Exception) {
                    getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_ACTIVE, false).apply()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    onRecordingStopped?.invoke(null)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Запись экрана BAKE", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val stopIntent = Intent(this, ScreenRecordingService::class.java).setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getService(
            this, 7403, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }.setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("BAKE Navigator")
            .setContentText("Идёт запись экрана для диагностики")
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "Остановить", stopPendingIntent)
            .build()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun beginRecording(resultCode: Int, data: Intent) {
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = manager.getMediaProjection(resultCode, data)
            ?: error("Android не предоставил MediaProjection")

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        val width = (metrics.widthPixels / 2) * 2
        val height = (metrics.heightPixels / 2) * 2
        val density = metrics.densityDpi

        val directory = File(getExternalFilesDir(Environment.DIRECTORY_MOVIES), "BAKE-Diagnostics")
        if (!directory.exists() && !directory.mkdirs()) error("Не удалось создать папку записи")
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        outputFile = File(directory, "bake_screen_$stamp.mp4")

        val mediaRecorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        recorder = mediaRecorder
        mediaRecorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        mediaRecorder.setVideoSize(width, height)
        mediaRecorder.setVideoFrameRate(30)
        mediaRecorder.setVideoEncodingBitRate(6_000_000)
        mediaRecorder.setOutputFile(outputFile!!.absolutePath)
        mediaRecorder.prepare()

        virtualDisplay = projection!!.createVirtualDisplay(
            "BAKE Navigator diagnostics",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            mediaRecorder.surface, null, null
        )
        mediaRecorder.start()
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putBoolean(KEY_ACTIVE, true)
            .apply()
    }

    private fun stopRecording() {
        if (stopping) return
        stopping = true
        try {
            virtualDisplay?.release()
            virtualDisplay = null
            recorder?.run {
                try { stop() } catch (_: RuntimeException) {}
                reset()
                release()
            }
            recorder = null
            projection?.stop()
            projection = null
            val saved = outputFile?.takeIf { it.exists() && it.length() > 1024L }?.absolutePath
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean(KEY_ACTIVE, false)
                .putString(KEY_LAST_FILE, saved)
                .apply()
            onRecordingStopped?.invoke(saved)
        } finally {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    override fun onDestroy() {
        if (!stopping) {
            try {
                virtualDisplay?.release()
                recorder?.release()
                projection?.stop()
            } catch (_: Exception) {}
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_ACTIVE, false).apply()
        }
        super.onDestroy()
    }
}
