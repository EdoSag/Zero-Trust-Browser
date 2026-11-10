package dev.sagron.zerotrustbrowser

import java.net.URLDecoder

/**
 * Removes tracking from links tapped on a page: click and campaign tags
 * (`utm_source`, `fbclid`, `gclid`...), redirect wrappers that report the
 * click before sending you on, and AMP copies hosted by Google.
 *
 * The rules ([params], [prefixes], [wrappers]) come from Dart
 * (lib/browser/clean_url.dart), which has the same logic for links that are
 * copied or shared; test/fixtures/clean_url_cases.json checks both.
 * Plain JVM code, no Android classes, so it can be run on its own.
 */
object LinkCleaner {
    class Wrapper(val host: String, val path: String, val param: String)

    @Volatile var enabled = true
    @Volatile var params: Set<String> = emptySet()
    @Volatile var prefixes: List<String> = emptyList()
    @Volatile var wrappers: List<Wrapper> = emptyList()

    private val hostName = Regex("^[A-Za-z0-9.-]+$")

    /** [url] without tracking; [url] itself when there is nothing to remove. */
    fun clean(url: String): String = if (enabled) clean(url, 0) else url

    /** The host of [url], lower case, without `www.`; empty when none. */
    fun hostOf(url: String): String {
        val start = url.indexOf("://")
        if (start < 0) return ""
        val from = start + 3
        var end = url.length
        for (c in charArrayOf('/', '?', '#')) {
            val i = url.indexOf(c, from)
            if (i in 0 until end) end = i
        }
        var host = url.substring(from, end).lowercase()
        val at = host.lastIndexOf('@')
        if (at >= 0) host = host.substring(at + 1)
        val port = host.indexOf(':')
        if (port >= 0) host = host.substring(0, port)
        return host.removePrefix("www.")
    }

    private fun clean(url: String, depth: Int): String {
        val lower = url.take(8).lowercase()
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) return url
        val hash = url.indexOf('#')
        val fragment = if (hash < 0) "" else url.substring(hash)
        val noFragment = if (hash < 0) url else url.substring(0, hash)
        val mark = noFragment.indexOf('?')
        val base = if (mark < 0) noFragment else noFragment.substring(0, mark)
        val query = if (mark < 0) "" else noFragment.substring(mark + 1)

        val host = hostOf(base)
        val pathStart = base.indexOf('/', base.indexOf("://") + 3)
        val path = if (pathStart < 0) "/" else base.substring(pathStart)

        if (depth < 3) {
            val amp = ampTarget(host, path)
            if (amp != null) {
                return clean(amp + (if (query.isEmpty()) "" else "?$query") + fragment, depth + 1)
            }
            if (query.isNotEmpty()) {
                for (w in wrappers) {
                    if ((host == w.host || host.endsWith("." + w.host)) && path.startsWith(w.path)) {
                        val target = queryValue(query, w.param)
                        if (target != null && (target.startsWith("https://") || target.startsWith("http://"))) {
                            return clean(target, depth + 1)
                        }
                    }
                }
            }
        }

        if (query.isEmpty()) return url
        val kept = ArrayList<String>()
        var dropped = false
        for (pair in query.split('&')) {
            val eq = pair.indexOf('=')
            val key = (if (eq < 0) pair else pair.substring(0, eq)).lowercase()
            if (isTracking(key)) dropped = true else kept.add(pair)
        }
        if (!dropped) return url
        return base + (if (kept.isEmpty()) "" else "?" + kept.joinToString("&")) + fragment
    }

    private fun isTracking(key: String): Boolean {
        if (key.isEmpty()) return false
        if (key in params) return true
        return prefixes.any { key.startsWith(it) }
    }

    private fun ampTarget(host: String, path: String): String? {
        var rest: String? = null
        if (host.endsWith(".cdn.ampproject.org")) {
            for (kind in arrayOf("/c/", "/v/")) {
                if (path.startsWith(kind)) rest = path.substring(kind.length)
            }
        } else if ((host == "google.com" || host.startsWith("google.")) && path.startsWith("/amp/")) {
            rest = path.substring(5)
        }
        var r = rest ?: return null
        val secure = r.startsWith("s/")
        if (secure) r = r.substring(2)
        val slash = r.indexOf('/')
        val target = if (slash < 0) r else r.substring(0, slash)
        if (!target.contains('.') || !hostName.matches(target)) return null
        return (if (secure) "https" else "http") + "://" + r
    }

    private fun queryValue(query: String, name: String): String? {
        for (pair in query.split('&')) {
            val eq = pair.indexOf('=')
            if (eq < 0) continue
            if (pair.substring(0, eq) == name) {
                return try {
                    URLDecoder.decode(pair.substring(eq + 1), "UTF-8")
                } catch (e: IllegalArgumentException) {
                    null
                }
            }
        }
        return null
    }
}
