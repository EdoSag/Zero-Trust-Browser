package dev.sagron.zerotrustbrowser

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/**
 * W13: a grid of the start page's quick links (or, until some are pinned,
 * the first bookmarks). A tap opens the site in ZT Browser. ZT Browser
 * hands the list over whenever it changes ([save]); it is kept encrypted
 * on this phone ([EncryptedStore]) and cleared on sign-out.
 *
 * Shared Zero-Trust widget look (Zero-Trust-Core/android-widget-kit).
 */
class LinksWidgetProvider : AppWidgetProvider() {

    companion object {
        /** Up to this many links (the start page shows 12 too). */
        const val MAX = 12

        private fun store(context: Context) = EncryptedStore(context, "widget-links")

        /** The links as (title, url), in order. */
        fun links(context: Context): List<Pair<String, String>> {
            val text = store(context).read() ?: return emptyList()
            return try {
                val arr = JSONArray(text)
                (0 until minOf(arr.length(), MAX)).mapNotNull { i ->
                    val o = arr.optJSONObject(i) ?: return@mapNotNull null
                    val url = o.optString("url")
                    if (!url.startsWith("https://") && !url.startsWith("http://")) return@mapNotNull null
                    o.optString("title").ifBlank { Uri.parse(url).host.orEmpty().removePrefix("www.") } to url
                }
            } catch (e: Exception) {
                emptyList()
            }
        }

        /** New links from ZT Browser ("[]" on sign-out); redraws the widgets. */
        fun save(context: Context, json: String) {
            val app = context.applicationContext
            if (store(app).read() == json) return
            store(app).write(json)
            val manager = AppWidgetManager.getInstance(app)
            val ids = manager.getAppWidgetIds(ComponentName(app, LinksWidgetProvider::class.java))
            if (ids.isEmpty()) return
            @Suppress("DEPRECATION")
            manager.notifyAppWidgetViewDataChanged(ids, R.id.links_grid)
            ids.forEach { manager.updateAppWidget(it, views(app, it)) }
        }

        private fun views(context: Context, id: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_links)
            val adapter = Intent(context, LinksWidgetService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            // Each widget its own adapter (the data makes the intents differ).
            adapter.data = Uri.parse(adapter.toUri(Intent.URI_INTENT_SCHEME))
            @Suppress("DEPRECATION")
            views.setRemoteAdapter(R.id.links_grid, adapter)
            views.setEmptyView(R.id.links_grid, R.id.links_empty)
            // A link's tap fills in its address (ACTION_VIEW: opens a tab).
            val open = Intent(context, MainActivity::class.java)
                .setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            views.setPendingIntentTemplate(
                R.id.links_grid,
                PendingIntent.getActivity(
                    context,
                    10,
                    open,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                ),
            )
            views.setOnClickPendingIntent(R.id.links_empty, SearchWidgetProvider.open(context, "search", 11))
            views.setOnClickPendingIntent(R.id.links_header, SearchWidgetProvider.open(context, "search", 11))
            return views
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, views(context, it)) }
    }
}

/** The cells of [LinksWidgetProvider]'s grid. */
class LinksWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    private class Factory(private val context: Context) : RemoteViewsFactory {
        private var links: List<Pair<String, String>> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            links = LinksWidgetProvider.links(context)
        }

        override fun onDestroy() {
            links = emptyList()
        }

        override fun getCount() = links.size

        override fun getViewAt(position: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_link_item)
            val (title, url) = links.getOrNull(position) ?: return views
            val letter = title.trim().firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: "•"
            views.setTextViewText(R.id.link_letter, letter)
            views.setTextViewText(R.id.link_title, title)
            views.setContentDescription(R.id.link_item, title)
            views.setOnClickFillInIntent(R.id.link_item, Intent().setData(Uri.parse(url)))
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount() = 1

        override fun getItemId(position: Int) = position.toLong()

        override fun hasStableIds() = false
    }
}
