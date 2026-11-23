package dev.sagron.zerotrustbrowser

import android.content.Context
import android.text.TextUtils
import android.webkit.WebResourceResponse
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * B-1: warnings for phishing and malware sites, from the signed list the
 * "Safety list" workflow publishes each day (see tool/update_safety_list.py
 * for the format). Lookups are on the phone: the address is hashed and
 * searched in the downloaded list, never sent anywhere.
 */
object SafeBrowsing {
    /** The setting "Warn about dangerous sites". */
    @Volatile var enabled = true

    @Volatile private var phishing = LongArray(0)
    @Volatile private var malware = LongArray(0)
    @Volatile var listDate = ""
        private set

    /** Texts of the warning page, in the app's language (from Dart). */
    @Volatile var labels: Map<String, String> = emptyMap()

    /** The special address the warning page's buttons go to. */
    const val ACTION_HOST = "zt-safety.invalid"

    private const val HEADER = "# ZT Browser safety list, format 1."
    private const val MAX_ENTRIES = 3_000_000

    private val loader = Executors.newSingleThreadExecutor()
    private var started = false

    fun file(context: Context) = File(context.filesDir, "safety/safety-list.bin")

    fun size() = phishing.size + malware.size

    /** Reads the downloaded list once, off the main thread. */
    fun load(context: Context) {
        if (started) return
        started = true
        reload(context)
    }

    fun reload(context: Context) {
        val app = context.applicationContext
        loader.execute {
            try {
                val f = file(app)
                if (!f.isFile) return@execute
                DataInputStream(f.inputStream().buffered()).use { read(it) }
            } catch (e: Exception) {
                android.util.Log.e("ZtBrowser", "Safety list not loaded", e)
            }
        }
    }

    private fun read(input: DataInputStream) {
        var date = ""
        var p = -1
        var m = -1
        var first = true
        while (true) {
            val line = readLine(input) ?: return
            if (first) {
                if (line != HEADER) return
                first = false
                continue
            }
            if (line.isEmpty()) break
            when {
                line.startsWith("# list-date: ") -> date = line.removePrefix("# list-date: ")
                line.startsWith("# phishing: ") -> p = line.removePrefix("# phishing: ").toIntOrNull() ?: -1
                line.startsWith("# malware: ") -> m = line.removePrefix("# malware: ").toIntOrNull() ?: -1
            }
        }
        if (p < 0 || m < 0 || p + m > MAX_ENTRIES) return
        val ph = LongArray(p) { input.readLong() }
        val mw = LongArray(m) { input.readLong() }
        phishing = ph
        malware = mw
        listDate = date
    }

    private fun readLine(input: DataInputStream): String? {
        val out = StringBuilder()
        while (out.length < 200) {
            val b = input.read()
            if (b < 0) return null
            if (b == '\n'.code) return out.toString()
            out.append(b.toChar())
        }
        return null
    }

    /**
     * "phishing" or "malware" when [host] or a site it belongs to is on the
     * list; null when it isn't, the list isn't there yet, or warnings are
     * off.
     */
    fun check(host: String?): String? {
        if (!enabled || host.isNullOrEmpty()) return null
        val p = phishing
        val m = malware
        if (p.isEmpty() && m.isEmpty()) return null
        var h = host.lowercase().trimEnd('.').removePrefix("www.")
        val digest = MessageDigest.getInstance("SHA-256")
        while (true) {
            val key = hash(digest, h)
            if (p.binarySearch(key) >= 0) return "phishing"
            if (m.binarySearch(key) >= 0) return "malware"
            val dot = h.indexOf('.')
            if (dot < 0 || h.indexOf('.', dot + 1) < 0) return null
            h = h.substring(dot + 1)
        }
    }

    private fun hash(digest: MessageDigest, host: String): Long {
        digest.reset()
        val d = digest.digest(host.toByteArray(Charsets.UTF_8))
        var v = 0L
        for (i in 0 until 8) v = (v shl 8) or (d[i].toLong() and 0xFF)
        return v
    }

    private fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback

    /**
     * The page shown instead of a dangerous site. It needs no JavaScript:
     * its two links go to [ACTION_HOST], which the tab answers itself.
     * Both carry [token], a secret only this warning knows, so another page
     * can't fake "Open the site anyway" by loading the link itself.
     */
    fun warningPage(url: String, host: String, kind: String, token: String): WebResourceResponse {
        val esc = { s: String -> TextUtils.htmlEncode(s) }
        val title = if (kind == "malware") {
            label("malwareTitle", "This site may harm your phone")
        } else {
            label("phishingTitle", "Deceptive site ahead")
        }
        val body = if (kind == "malware") {
            label("malwareBody", "It is known for spreading harmful apps and files.")
        } else {
            label("phishingBody", "It may try to trick you into giving away a password, card number or code.")
        }
        val back = "https://$ACTION_HOST/back?t=$token"
        val proceed = "https://$ACTION_HOST/proceed?t=$token"
        val dir = if (label("dir", "ltr") == "rtl") "rtl" else "ltr"
        val html = """<!doctype html><html dir="$dir"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light">
<title>${esc(title)}</title><style>
body{margin:0;font-family:sans-serif;background:#7f1d1d;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{max-width:34em;padding:32px 24px}h1{font-size:1.5em;margin:16px 0}p{line-height:1.5}
.host{direction:ltr;unicode-bidi:embed;font-weight:bold;word-break:break-all}
a.b{display:block;text-align:center;background:#fff;color:#7f1d1d;padding:14px;border-radius:24px;text-decoration:none;font-weight:bold;margin:28px 0 20px}
details{opacity:.85}summary{cursor:pointer}a.p{color:#fff}
</style></head><body><main><div style="font-size:48px">&#9888;</div><h1>${esc(title)}</h1>
<p><span class="host">${esc(host)}</span></p><p>${esc(body)}</p>
<a class="b" href="${esc(back)}">${esc(label("back", "Back to safety"))}</a>
<details><summary>${esc(label("details", "Details"))}</summary>
<p>${esc(label("detailsBody", "ZT Browser checked this address on your phone against a public list of dangerous sites. Nothing was sent anywhere."))}</p>
<p><a class="p" href="${esc(proceed)}">${esc(label("proceed", "Open the site anyway (not safe)"))}</a></p>
</details></main></body></html>"""
        return WebResourceResponse(
            "text/html", "utf-8", 200, "OK",
            mapOf("Cache-Control" to "no-store"),
            ByteArrayInputStream(html.toByteArray(Charsets.UTF_8)),
        )
    }
}
