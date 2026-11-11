package dev.sagron.zerotrustbrowser

import android.content.Context
import io.flutter.FlutterInjector
import java.io.BufferedReader
import java.io.File
import java.util.concurrent.Executors

/**
 * Blocks requests to known ad and tracker hosts, and hides ad boxes and
 * cookie banners, from EasyList, EasyPrivacy and the EasyList Cookie List
 * (`assets/blocklist/blocklist.txt`, built by `tool/update_blocklist.py`).
 *
 * A host is blocked when it, or any domain above it, is listed: listing
 * `tracker.com` blocks `cdn.tracker.com` too. Hosts marked `3p` are only
 * blocked when another site loads them, so visiting the site itself works.
 * Lookups are hash-set reads, cheap enough for every request of a page.
 *
 * A newer signed list downloaded by the app (see `blocklist_updater.dart`)
 * replaces the bundled one: `files/blocklist/blocklist.txt`.
 */
object Blocker {
    @Volatile private var everywhere: Set<String> = emptySet()
    @Volatile private var thirdPartyOnly: Set<String> = emptySet()

    /** CSS hiding generic ad boxes and cookie banners, on every site. */
    @Volatile var genericCss: String = ""
        private set

    /** Sites where the generic CSS breaks something, per the list. */
    @Volatile var genericOff: Set<String> = emptySet()
        private set
    @Volatile private var siteHide: Map<String, List<String>> = emptyMap()

    /** The list's date (yyyy-mm-ddThh:mm UTC), to tell whether a download is newer. */
    @Volatile var listDate: String = ""
        private set
    @Volatile var fromUpdate = false
        private set

    /** User settings, pushed from Dart (`setPrivacy`). */
    @Volatile var enabled = true
    @Volatile var hideElements = true

    /** Sites (registrable domains) where the user turned protection off. */
    @Volatile var allowedSites: Set<String> = emptySet()

    /** The user's own rules (B30): hosts always blocked, and never blocked. */
    @Volatile var userBlocked: Set<String> = emptySet()
    @Volatile var userAllowed: Set<String> = emptySet()

    /** Hosts from the user's extra filter lists, read from a file. */
    @Volatile private var extraHosts: Set<String> = emptySet()
    @Volatile private var extraFile: String? = null

    /** How many hosts the extra lists add. */
    fun extraSize(): Int = extraHosts.size

    /**
     * Sets the user's rules; [listsFile] (one host per line) is read off the
     * main thread when it changed.
     */
    fun setUserRules(blocked: Set<String>, allowed: Set<String>, listsFile: String?) {
        userBlocked = blocked
        userAllowed = allowed
        if (listsFile == null) {
            extraFile = null
            extraHosts = emptySet()
            return
        }
        val file = File(listsFile)
        val stamp = listsFile + ":" + file.lastModified() + ":" + file.length()
        if (stamp == extraFile) return
        extraFile = stamp
        loader.execute {
            try {
                val set = HashSet<String>()
                file.bufferedReader().use { r ->
                    r.forEachLine { line ->
                        val h = line.trim()
                        if (h.isNotEmpty()) set.add(h)
                    }
                }
                extraHosts = set
            } catch (e: Exception) {
                android.util.Log.e("ZtBrowser", "Filter lists not loaded", e)
            }
        }
    }

    /** [host] or a domain above it is in [set]. */
    private fun listed(host: String, set: Set<String>): Boolean {
        if (set.isEmpty()) return false
        var d = host
        while (true) {
            if (d in set) return true
            val dot = d.indexOf('.')
            if (dot < 0) return false
            d = d.substring(dot + 1)
        }
    }

    /** Called on the main thread when a list has loaded, to refresh tabs. */
    @Volatile var onLoaded: (() -> Unit)? = null

    private val loader = Executors.newSingleThreadExecutor()
    private var started = false

    fun updateFile(context: Context) = File(context.filesDir, "blocklist/blocklist.txt")

    /** Reads the list once, off the main thread. Requests before it's done pass. */
    fun load(context: Context) {
        if (started) return
        started = true
        reload(context)
    }

    /** Reads the newer of the bundled and the downloaded list. */
    fun reload(context: Context) {
        val app = context.applicationContext
        loader.execute {
            try {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/blocklist/blocklist.txt")
                val bundledDate = app.assets.open(key).bufferedReader().use { dateOf(it) }
                val update = updateFile(app)
                val updateDate = if (update.isFile) update.bufferedReader().use { dateOf(it) } else ""
                if (updateDate.isNotEmpty() && updateDate > bundledDate) {
                    update.bufferedReader().use { parse(it) }
                    fromUpdate = true
                } else {
                    app.assets.open(key).bufferedReader().use { parse(it) }
                    fromUpdate = false
                }
                android.os.Handler(android.os.Looper.getMainLooper()).post { onLoaded?.invoke() }
            } catch (e: Exception) {
                android.util.Log.e("ZtBrowser", "Blocklist not loaded", e)
            }
        }
    }

    private val DATE = Regex("^# list-date: ([0-9T:-]{10,16})")

    private fun dateOf(reader: BufferedReader): String {
        for (i in 0 until 20) {
            val line = reader.readLine() ?: break
            DATE.find(line)?.let { return it.groupValues[1] }
            if (line.startsWith("!")) break
        }
        return ""
    }

    private fun parse(reader: BufferedReader) {
        val all = HashSet<String>(60_000)
        val third = HashSet<String>(8_000)
        val generic = ArrayList<String>(30_000)
        val off = HashSet<String>(2_000)
        val sites = HashMap<String, MutableList<String>>(25_000)
        var section = ""
        var date = ""
        reader.forEachLine { line ->
            if (line.isEmpty()) return@forEachLine
            if (line[0] == '!') {
                section = line.substring(1)
                return@forEachLine
            }
            when (section) {
                // Before the first section, # lines are comments.
                "" -> DATE.find(line)?.let { date = it.groupValues[1] }
                "hosts" -> {
                    val space = line.indexOf(' ')
                    if (space < 0) all.add(line) else third.add(line.substring(0, space))
                }
                "hide" -> generic.add(line)
                "hide-off" -> off.add(line)
                "site-hide" -> {
                    val space = line.indexOf(' ')
                    if (space > 0) {
                        sites.getOrPut(line.substring(0, space)) { ArrayList(2) }
                            .add(line.substring(space + 1))
                    }
                }
            }
        }
        everywhere = all
        thirdPartyOnly = third
        genericCss = cssOf(generic)
        genericOff = off
        siteHide = sites
        listDate = date
    }

    /**
     * Selectors grouped 100 to a rule: few rules to parse, and a selector
     * the engine doesn't understand only voids its own group.
     */
    private fun cssOf(selectors: List<String>): String {
        val sb = StringBuilder(selectors.sumOf { it.length + 1 } + selectors.size / 2)
        selectors.chunked(100).forEach { group ->
            sb.append(group.joinToString(",")).append("{display:none!important}\n")
        }
        return sb.toString()
    }

    /** The number of hosts in the list, for the settings screen. */
    fun size(): Int = everywhere.size + thirdPartyOnly.size

    /** Whether the user's protection applies on [pageHost]'s site. */
    fun protects(pageHost: String?): Boolean {
        if (!enabled) return false
        val page = pageHost?.lowercase() ?: return true
        return siteOf(page) !in allowedSites
    }

    /**
     * Whether a request to [host] made by a page on [pageHost] should be
     * blocked. Top-level pages are never blocked: the user asked for them.
     */
    fun shouldBlock(host: String?, pageHost: String?): Boolean {
        if (!enabled || host.isNullOrEmpty()) return false
        val h = host.lowercase()
        val page = pageHost?.lowercase()
        if (page != null && siteOf(page) in allowedSites) return false
        // The user's own "never block" wins over every list.
        if (listed(h, userAllowed)) return false
        if (listed(h, userBlocked) || listed(h, extraHosts)) return true
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

    /** CSS hiding this site's own ad boxes and cookie banners, or null. */
    fun siteCss(pageHost: String?): String? {
        if (!enabled || !hideElements || pageHost.isNullOrEmpty() || !protects(pageHost)) return null
        val found = ArrayList<String>()
        var d = pageHost.lowercase()
        while (true) {
            siteHide[d]?.let { found.addAll(it) }
            val dot = d.indexOf('.')
            if (dot < 0) break
            d = d.substring(dot + 1)
        }
        if (found.isEmpty()) return null
        return cssOf(found)
    }

    /**
     * The registrable domain ("site") of [host], close enough without the
     * full public-suffix list: the last two labels, or three for two-letter
     * country domains with a short second level (`bbc.co.uk`, `abc.com.au`).
     * The page script (`PageScripts.SITE_OF`) does the same in JavaScript.
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
