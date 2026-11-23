package dev.sagron.zerotrustbrowser

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

/**
 * W13: a 1x1 Fire button for the home screen. A tap opens ZT Browser,
 * which at once deletes cookies, site data, the cache and private
 * downloads (before any unlock), then closes every tab and deletes the last
 * hour of history once unlocked, like the Fire button's default.
 */
class FireWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = RemoteViews(context.packageName, R.layout.widget_fire)
        views.setOnClickPendingIntent(R.id.fire_root, SearchWidgetProvider.open(context, "fire", 20))
        ids.forEach { manager.updateAppWidget(it, views) }
    }
}
