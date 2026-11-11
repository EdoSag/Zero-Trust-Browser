package dev.sagron.zerotrustbrowser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder

/**
 * What is playing now, for the notification (B26, B27): a page's audio or
 * video, or read aloud. One at a time: whichever started last.
 */
object MediaHub {
    data class Now(
        /** "web" (a page's media) or "speech" (read aloud). */
        val source: String,
        val tabId: String?,
        val title: String,
        val site: String,
        val playing: Boolean,
        val private: Boolean,
    )

    @Volatile var now: Now? = null
        private set

    /** Texts in the app's language, pushed from Dart (`setMedia`). */
    @Volatile var labels: Map<String, String> = emptyMap()

    /** Play, pause and stop from the notification, handled by the activity. */
    @Volatile var control: ((String) -> Unit)? = null

    /** The running service, to redraw its notification. */
    @Volatile var listener: (() -> Unit)? = null

    fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback

    fun set(context: Context, value: Now?) {
        now = value
        if (value == null) {
            context.stopService(Intent(context, MediaService::class.java))
            return
        }
        val l = listener
        if (l != null) {
            l()
            return
        }
        if (!value.playing) return
        try {
            context.startForegroundService(Intent(context, MediaService::class.java))
        } catch (e: Exception) {
            // Not allowed from the background (Android 12+): no notification
            // this time; it appears when playback starts with the app open.
            android.util.Log.w("ZtBrowser", "Media notification not started", e)
        }
    }
}

/**
 * A foreground service with a media notification, so audio and read aloud
 * keep going with the app in the background, and can be paused, resumed
 * or stopped from the notification and the lock screen. A private tab's
 * page title never shows there.
 */
class MediaService : Service() {
    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val s = MediaSession(this, "ZtBrowser")
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = MediaHub.control?.invoke("play") ?: Unit
            override fun onPause() = MediaHub.control?.invoke("pause") ?: Unit
            override fun onStop() = MediaHub.control?.invoke("stop") ?: Unit
        })
        s.isActive = true
        session = s
        MediaHub.listener = { refresh() }
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(CHANNEL, MediaHub.label("channel", "Playing media"), NotificationManager.IMPORTANCE_LOW)
                .apply { setShowBadge(false) },
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> MediaHub.control?.invoke("play")
            ACTION_PAUSE -> MediaHub.control?.invoke("pause")
            ACTION_STOP -> MediaHub.control?.invoke("stop")
        }
        val notification = build()
        if (notification == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun refresh() {
        val n = build() ?: run {
            stopSelf()
            return
        }
        getSystemService(NotificationManager::class.java)?.notify(ID, n)
    }

    private fun build(): Notification? {
        val now = MediaHub.now ?: return null
        val s = session ?: return null
        val title = when {
            now.private -> MediaHub.label("privateTab", "Private tab")
            now.title.isNotBlank() -> now.title
            else -> now.site
        }
        val subtitle = if (now.source == "speech") MediaHub.label("readingAloud", "Reading aloud") else if (now.private) "" else now.site
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .build(),
        )
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP)
                .setState(if (now.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f)
                .build(),
        )
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val toggle = if (now.playing) {
            action(ACTION_PAUSE, R.drawable.ic_zt_notify_pause, MediaHub.label("pause", "Pause"), 1)
        } else {
            action(ACTION_PLAY, R.drawable.ic_zt_notify_play, MediaHub.label("play", "Play"), 2)
        }
        val stop = action(ACTION_STOP, R.drawable.ic_zt_notify_stop, MediaHub.label("stop", "Stop"), 3)
        val builder = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_zt_notify)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setContentIntent(open)
            .setOngoing(now.playing)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(if (now.private) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PUBLIC)
            .addAction(toggle)
            .addAction(stop)
            .setStyle(Notification.MediaStyle().setMediaSession(s.sessionToken).setShowActionsInCompactView(0, 1))
            .setDeleteIntent(service(ACTION_STOP, 4))
        return builder.build()
    }

    private fun service(action: String, code: Int): PendingIntent = PendingIntent.getService(
        this, code,
        Intent(this, MediaService::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun action(name: String, icon: Int, label: String, code: Int): Notification.Action =
        Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, icon),
            label,
            service(name, code),
        ).build()

    override fun onDestroy() {
        MediaHub.listener = null
        session?.release()
        session = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "media"
        private const val ID = 4201
        const val ACTION_PLAY = "dev.sagron.zerotrustbrowser.PLAY"
        const val ACTION_PAUSE = "dev.sagron.zerotrustbrowser.PAUSE"
        const val ACTION_STOP = "dev.sagron.zerotrustbrowser.STOP"
    }
}
