package dev.sagron.zerotrustbrowser

import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebStorage

/**
 * Wipes what sites left in normal tabs (B24): cookies, and site storage
 * (local storage, IndexedDB, caches, service workers) of whole sites.
 * Private tabs have their own profile and are never touched here.
 */
object SiteData {
    private const val EXPIRED = "=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT"

    /**
     * [entries] are hosts ("example.com") or hosts with a page path
     * ("example.com/account/settings"): cookies limited to a path are only
     * listed when asked for that path, so each recorded path is checked,
     * and each cookie found is expired at every path it could have.
     */
    fun clear(entries: List<String>, done: () -> Unit) {
        val cookies = CookieManager.getInstance()
        val paths = HashMap<String, MutableSet<String>>()
        for (e in entries) {
            val host = e.substringBefore('/').lowercase().trim('.')
            if (host.isEmpty()) continue
            val path = if (e.contains('/')) "/" + e.substringAfter('/') else "/"
            paths.getOrPut(host) { mutableSetOf("/") }.add(path)
        }
        val sites = paths.keys.map { Blocker.siteOf(it) }.toSet()
        for (h in sites + sites.map { "www.$it" }) paths.getOrPut(h) { mutableSetOf("/") }
        for ((h, hostPaths) in paths) {
            val site = Blocker.siteOf(h)
            for (path in hostPaths) {
                // "/a/b/c" may hold cookies set for "/", "/a", "/a/b" or "/a/b/c".
                val segments = path.split('/').filter { it.isNotEmpty() }
                val prefixes = listOf("/") + segments.indices.map { "/" + segments.take(it + 1).joinToString("/") }
                for (scheme in listOf("https", "http")) {
                    val url = "$scheme://$h$path"
                    val found = cookies.getCookie(url) ?: continue
                    val secure = if (scheme == "https") "; Secure" else ""
                    for (pair in found.split(';')) {
                        val name = pair.substringBefore('=').trim()
                        if (name.isEmpty()) continue
                        // A cookie is only replaced by one with the same
                        // domain and path: try host-only, the host and the
                        // site, at each path.
                        for (p in prefixes) {
                            val at = "$EXPIRED; Path=${Uri.decode(p)}$secure"
                            cookies.setCookie(url, name + at)
                            cookies.setCookie(url, "$name$at; Domain=$h")
                            if (site != h) cookies.setCookie(url, "$name$at; Domain=.$site")
                        }
                    }
                }
            }
        }
        cookies.flush()
        val storage = WebStorage.getInstance()
        storage.getOrigins { origins ->
            try {
                for (key in origins?.keys ?: emptySet<Any?>()) {
                    val origin = key?.toString() ?: continue
                    val host = Uri.parse(origin).host?.lowercase() ?: continue
                    if (Blocker.siteOf(host) in sites) storage.deleteOrigin(origin)
                }
            } finally {
                done()
            }
        }
    }
}
