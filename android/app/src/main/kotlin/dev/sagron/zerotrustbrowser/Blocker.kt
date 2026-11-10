package dev.sagron.zerotrustbrowser

import android.content.Context
import io.flutter.FlutterInjector
import java.util.concurrent.Executors

/**
 * Blocks requests to known ad and tracker hosts, from the EasyList and
 * EasyPrivacy host rules in `assets/blocklist/domains.txt` (built by
 * `tool/update_blocklist.py`).
 *
 * A host is blocked when it, or any domain above it, is listed: listing
 * `tracker.com` blocks `cdn.tracker.com` too. Hosts marked `3p` are only
 * blocked when another site loads them, so visiting the site itself works.
 * Lookups are hash-set reads, cheap enough for every request of a page.
 */
object Blocker {
    @Volatile private var everywhere: Set<String> = emptySet()
    @Volatile private var thirdPartyOnly: Set<String> = emptySet()
    @Volatile private var loaded = false

    /** User settings, pushed from Dart (`setPrivacy`). */
    @Volatile var enabled = true

    /** Sites (registrable domains) where the user turned protection off. */
    @Volatile var allowedSites: Set<String> = emptySet()

    private val loader = Executors.newSingleThreadExecutor()

    /** Reads the list once, off the main thread. Requests before it's done pass. */
    fun load(context: Context) {
        if (loaded) return
        loaded = true
        val app = context.applicationContext
        loader.execute {
            try {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/blocklist/domains.txt")
                val all = HashSet<String>(60_000)
                val third = HashSet<String>(8_000)
                app.assets.open(key).bufferedReader().useLines { lines ->
                    for (line in lines) {
                        if (line.isEmpty() || line[0] == '#') continue
                        val space = line.indexOf(' ')
                        if (space < 0) all.add(line) else third.add(line.substring(0, space))
                    }
                }
                everywhere = all
                thirdPartyOnly = third
            } catch (e: Exception) {
                android.util.Log.e("ZtBrowser", "Blocklist not loaded", e)
            }
        }
    }

    /** The number of hosts in the list, for the settings screen. */
    fun size(): Int = everywhere.size + thirdPartyOnly.size

    /**
     * Whether a request to [host] made by a page on [pageHost] should be
     * blocked. Top-level pages are never blocked: the user asked for them.
     */
    fun shouldBlock(host: String?, pageHost: String?): Boolean {
        if (!enabled || host.isNullOrEmpty()) return false
        val h = host.lowercase()
        val page = pageHost?.lowercase()
        if (page != null && siteOf(page) in allowedSites) return false
        val sameSite = page != null && siteOf(page) == siteOf(h)
        var d = h
        while (true) {
            if (d in everywhere) return true
            if (!sameSite && d in thirdPartyOnly) return true
            val dot = d.indexOf('.')
            if (dot < 0 || d.indexOf('.', dot + 1) < 0) return false
            d = d.substring(dot + 1)
        }
    }

    /**
     * The registrable domain ("site") of [host], close enough without the
     * full public-suffix list: the last two labels, or three for two-letter
     * country domains with a short second level (`bbc.co.uk`, `abc.com.au`).
     */
    fun siteOf(host: String): String {
        val labels = host.trimEnd('.').split('.')
        if (labels.size <= 2) return host
        val tld = labels[labels.size - 1]
        val second = labels[labels.size - 2]
        val keep = if (tld.length == 2 && second.length <= 3) 3 else 2
        return labels.takeLast(keep).joinToString(".")
    }
}
