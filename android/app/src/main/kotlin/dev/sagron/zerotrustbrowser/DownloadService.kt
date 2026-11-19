package dev.sagron.zerotrustbrowser

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import java.util.Collections

/**
 * Keeps downloads going with the app in the background (B34), with their
 * progress and Pause and Cancel in a notification. A private download's
 * name never shows there (B33), and private ones are hidden on the lock
 * screen.
 */
class DownloadService : Service() {
    private lateinit var engine: DownloadEngine
    private val refresh: () -> Unit = { update() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        engine = DownloadEngine.get(this)
        channels(this)
        engine.onChanged.add(refresh)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val key = intent?.getStringExtra(EXTRA_KEY)
        when (intent?.action) {
            ACTION_PAUSE -> key?.let(engine::pause)
            ACTION_CANCEL -> key?.let(engine::delete)
        }
        // Android requires the notification right away, even when nothing is left.
        val n = build() ?: placeholder()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, n)
        }
        if (!engine.anyActive()) stop()
        return START_NOT_STICKY
    }

    /** Android 15's daily limit for background transfers: pause, resume later. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        for (job in engine.list().filter { it.active }) engine.pause(job.key)
        stop()
    }

    private fun update() {
        if (!engine.anyActive()) {
            stop()
            return
        }
        val n = build() ?: return
        getSystemService(NotificationManager::class.java)?.notify(ID, n)
    }

    private fun stop() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun placeholder(): Notification = Notification.Builder(this, CHANNEL)
        .setSmallIcon(R.drawable.ic_zt_notify)
        .setContentTitle(engine.label("downloading", "Downloading"))
        .build()

    private fun build(): Notification? {
        val active = engine.list().filter { it.active }
        if (active.isEmpty()) return null
        val anyPrivate = active.any { it.private }
        val one = active.singleOrNull()
        val title = when {
            one == null -> engine.label("downloadingCount", "Downloading %d files").replace("%d", active.size.toString())
            one.private -> engine.label("privateDownload", "Private download")
            else -> one.name
        }
        val bytes = active.sumOf { it.bytes }
        val totals = active.map { it.total }
        val known = totals.all { it > 0 }
        val text = when {
            active.all { it.status == "waiting" } -> engine.label("waiting", "Waiting for a connection")
            known -> "${percent(bytes, totals.sum())}%"
            else -> engine.label("downloading", "Downloading")
        }
        val builder = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setProgress(100, if (known) percent(bytes, totals.sum()) else 0, !known)
            .setContentIntent(SearchWidgetProvider.open(this, "downloads", REQUEST_OPEN))
            .setVisibility(if (anyPrivate) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PRIVATE)
        if (one != null) {
            if (one.resumable) builder.addAction(action(ACTION_PAUSE, one.key, engine.label("pause", "Pause"), 1))
            builder.addAction(action(ACTION_CANCEL, one.key, engine.label("cancel", "Cancel"), 2))
        }
        return builder.build()
    }

    private fun percent(done: Long, total: Long): Int =
        if (total <= 0) 0 else (done * 100 / total).toInt().coerceIn(0, 100)

    private fun action(name: String, key: String, label: String, code: Int): Notification.Action =
        Notification.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_zt_notify),
            label,
            PendingIntent.getService(
                this, code,
                Intent(this, DownloadService::class.java).setAction(name).putExtra(EXTRA_KEY, key),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()

    override fun onDestroy() {
        engine.onChanged.remove(refresh)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val CHANNEL_DONE = "downloads_done"
        private const val ID = 4301
        private const val REQUEST_OPEN = 4300
        private const val EXTRA_KEY = "key"
        const val ACTION_PAUSE = "dev.sagron.zerotrustbrowser.DOWNLOAD_PAUSE"
        const val ACTION_CANCEL = "dev.sagron.zerotrustbrowser.DOWNLOAD_CANCEL"

        /** Finished notifications for private downloads, removed with them. */
        private val privateIds = Collections.synchronizedSet(HashSet<Int>())

        private fun channels(context: Context) {
            val engine = DownloadEngine.get(context)
            context.getSystemService(NotificationManager::class.java)?.apply {
                createNotificationChannel(
                    NotificationChannel(CHANNEL, engine.label("channel", "Downloads"), NotificationManager.IMPORTANCE_LOW)
                        .apply { setShowBadge(false) },
                )
                createNotificationChannel(
                    NotificationChannel(CHANNEL_DONE, engine.label("channelDone", "Finished downloads"), NotificationManager.IMPORTANCE_DEFAULT),
                )
            }
        }

        fun start(context: Context) {
            try {
                context.startForegroundService(Intent(context, DownloadService::class.java))
            } catch (e: Exception) {
                // Not allowed from the background (Android 12+): the download
                // still runs while the app is open, just without the notification.
                android.util.Log.w("ZtBrowser", "Download notification not started", e)
            }
        }

        /** "Download complete" or "Download failed"; private ones without the name. */
        fun finished(context: Context, job: DownloadEngine.Job) {
            val engine = DownloadEngine.get(context)
            channels(context)
            val done = job.status == "done"
            val title = engine.label(if (done) "complete" else "failed", if (done) "Download complete" else "Download failed")
            val id = ID + 1 + (job.key.hashCode() and 0xffff)
            val n = Notification.Builder(context, CHANNEL_DONE)
                .setSmallIcon(if (done) android.R.drawable.stat_sys_download_done else R.drawable.ic_zt_notify)
                .setContentTitle(title)
                .setContentText(if (job.private) engine.label("privateDownload", "Private download") else job.name)
                .setAutoCancel(true)
                .setContentIntent(SearchWidgetProvider.open(context, "downloads", REQUEST_OPEN))
                .setVisibility(if (job.private) Notification.VISIBILITY_SECRET else Notification.VISIBILITY_PRIVATE)
                .build()
            if (job.private) privateIds.add(id)
            try {
                context.getSystemService(NotificationManager::class.java)?.notify(id, n)
            } catch (e: SecurityException) {
                // Notifications are off for the app.
            }
        }

        /** The private session ended: its notifications go too. */
        fun clearPrivate(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            synchronized(privateIds) {
                privateIds.forEach { manager.cancel(it) }
                privateIds.clear()
            }
        }
    }
}
