package dev.sagron.zerotrustbrowser

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

/**
 * Home screen search bar (roadmap W12): search, voice, a new private tab and
 * a QR scan, each opening ZT Browser. It stores and shows nothing, so it
 * works the same whether the browser is locked or not; the browser asks to
 * unlock first as usual, then does what was tapped (`consumeWidgetAction`).
 *
 * Shared Zero-Trust widget look (Zero-Trust-Core/android-widget-kit).
 */
class SearchWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val ACTION = "dev.sagron.zerotrustbrowser.WIDGET"
        private const val EXTRA = "widget_action"
        private val KNOWN = setOf("search", "voice", "private", "qr")

        /** The widget button behind [intent], or null when it isn't a widget tap. */
        fun actionFrom(intent: Intent?): String? {
            if (intent?.action != ACTION) return null
            return intent.getStringExtra(EXTRA)?.takeIf { it in KNOWN }
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, buildViews(context, manager.getAppWidgetOptions(it))) }
    }

    /** Resized: show the round buttons that fit. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        manager.updateAppWidget(id, buildViews(context, options))
    }

    private fun buildViews(context: Context, options: Bundle?): RemoteViews {
        // Portrait width; 0 when the launcher hasn't said yet.
        val width = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0
        val views = RemoteViews(context.packageName, R.layout.widget_search_bar)
        fun show(id: Int, minWidth: Int) =
            views.setViewVisibility(id, if (width == 0 || width >= minWidth) View.VISIBLE else View.GONE)
        show(R.id.voice_button, 200)
        show(R.id.private_button, 250)
        show(R.id.qr_button, 300)
        views.setOnClickPendingIntent(R.id.widget_root, open(context, "search", 0))
        views.setOnClickPendingIntent(R.id.search_box, open(context, "search", 0))
        views.setOnClickPendingIntent(R.id.voice_button, open(context, "voice", 1))
        views.setOnClickPendingIntent(R.id.private_button, open(context, "private", 2))
        views.setOnClickPendingIntent(R.id.qr_button, open(context, "qr", 3))
        return views
    }

    private fun open(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA, action)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
