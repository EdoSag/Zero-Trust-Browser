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
    private const val EXPIRED = "=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/"

    fun clear(hosts: List<String>, done: () -> Unit) {
        val cookies = CookieManager.getInstance()
        val lower = hosts.map { it.lowercase().trim('.') }.filter { it.isNotEmpty() }
        val sites = lower.map { Blocker.siteOf(it) }.toSet()
        val all = (lower + sites + sites.map { "www.$it" }).toSet()
        for (h in all) {
            val site = Blocker.siteOf(h)
            for (scheme in listOf("https", "http")) {
                val url = "$scheme://$h/"
                val found = cookies.getCookie(url) ?: continue
                val secure = if (scheme == "https") "; Secure" else ""
                for (pair in found.split(';')) {
                    val name = pair.substringBefore('=').trim()
                    if (name.isEmpty()) continue
                    // A cookie is only replaced by one with the same domain
                    // and path: try host-only, the host, and the site.
                    cookies.setCookie(url, name + EXPIRED + secure)
                    cookies.setCookie(url, "$name$EXPIRED; Domain=$h$secure")
                    if (site != h) cookies.setCookie(url, "$name$EXPIRED; Domain=.$site$secure")
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
