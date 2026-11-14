package dev.sagron.zerotrustbrowser

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.ScriptHandler
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebMessagePortCompat
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/**
 * One browser tab: a WebView that outlives the Flutter widget showing it,
 * so switching tabs or locking the app keeps the page as it was. Dart
 * closes it with `closeTab`; the activity may also unload it when memory
 * runs low, keeping its history to restore it later.
 *
 * Privacy defaults: trackers blocked ([Blocker]), ad boxes and cookie
 * banners hidden, fingerprinting noise ([PageScripts]), third-party cookies
 * off, no file or content access, no mixed content, popups only on a tap,
 * camera, microphone and location only after the user agrees, Global
 * Privacy Control sent. Private tabs use their own WebView profile
 * (cookies, storage, cache), removed when the last private tab closes.
 */
@SuppressLint("SetJavaScriptEnabled")
class ZtTab(
    private val activity: Activity,
    val id: String,
    val isPrivate: Boolean,
    desktop: Boolean,
    private val events: (String, Map<String, Any?>) -> Unit,
    private val host: TabHost,
) {
    /** What a tab needs from the activity. */
    interface TabHost {
        fun showFileChooser(
            callback: ValueCallback<Array<Uri>>,
            params: WebChromeClient.FileChooserParams,
        ): Boolean

        fun showFullscreen(view: View, onHidden: () -> Unit)
        fun hideFullscreen()
        fun download(tab: ZtTab, url: String, userAgent: String, disposition: String?, mime: String?)
        fun onCrashed(tab: ZtTab)

        /**
         * Asks the user (through Dart) whether [origin] may use [kinds]
         * ("camera", "microphone", "location"); [answer] gets those allowed
         * by both the user and Android.
         */
        fun askPermission(tab: ZtTab, origin: String, kinds: List<String>, answer: (Set<String>) -> Unit)

        /**
         * A page's audio or video started or paused (B26); [title] null
         * when it is gone (new page, tab closed).
         */
        fun mediaChanged(tab: ZtTab, playing: Boolean, title: String?)
    }

    val webView: WebView = WebView(activity)
    private val main = Handler(Looper.getMainLooper())
    private val blocked = AtomicInteger(0)
    private val defaultUserAgent: String
    private var startScript: ScriptHandler? = null
    private var mediaScript: ScriptHandler? = null

    /** B41: the user's scripts, added after the browser's own. */
    private var userScripts: List<ScriptHandler> = emptyList()

    /** Commands the page's user scripts added (GM_registerMenuCommand). */
    private val scriptMenus = LinkedHashMap<String, Pair<JavaScriptReplyProxy, JSONArray>>()

    /** The frame whose media played last, to pause or play it again. */
    private var mediaFrame: JavaScriptReplyProxy? = null
    var mediaPlaying = false
        private set

    /** Host of the page now showing, read by the network thread. */
    @Volatile private var pageHost: String? = null

    /** http:// URLs this tab upgraded to https, to explain a failure. */
    private val upgraded = HashMap<String, String>()

    /** Hosts the user agreed to load over plain http in this tab. */
    private val insecureAllowed = HashSet<String>()

    /** Links this tab removed tracking from since the last finished page. */
    private val cleaned = HashSet<String>()
    private var stateQueued = false
    private var progress = 0
    private var loading = false
    private var sslError = false
    private var desktopMode = desktop
    private var readerable = false
    private var readerPending = false
    private var inReader = false

    /** The URL a JavaScript on/off switch last reloaded, to never loop. */
    private var jsReloadedFor: String? = null

    init {
        if (isPrivate && privateProfileSupported()) {
            // Must come before anything else touches the WebView.
            WebViewCompat.setProfile(webView, PRIVATE_PROFILE)
        }
        val s = webView.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        s.allowFileAccess = false
        s.allowContentAccess = false
        s.mediaPlaybackRequiresUserGesture = true
        s.setSupportMultipleWindows(true)
        s.javaScriptCanOpenWindowsAutomatically = false
        s.builtInZoomControls = true
        s.displayZoomControls = false
        s.useWideViewPort = true
        s.loadWithOverviewMode = true
        s.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        // Sites still need the user's yes (onGeolocationPermissionsShowPrompt).
        s.setGeolocationEnabled(true)
        if (isPrivate) {
            @Suppress("DEPRECATION")
            s.saveFormData = false
            // Without its own profile, at least nothing is kept in the cache.
            if (!privateProfileSupported()) s.cacheMode = WebSettings.LOAD_NO_CACHE
        }
        // Password managers fill sign-in forms through Android's autofill,
        // in private tabs too (nothing is saved by the browser itself).
        webView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
        // Look like Chrome rather than an in-app WebView ("; wv" makes some
        // sign-in pages refuse), and keep the original for desktop mode.
        defaultUserAgent = s.userAgentString
            .replace("; wv)", ")")
            .replace(Regex("Version/\\d+\\.\\d+ "), "")
        applyUserAgent()
        applyDisplay()
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        listenForMedia()
        listenForUserScripts()
        refreshScripts()
        webView.webViewClient = Client()
        webView.webChromeClient = Chrome()
        webView.setDownloadListener { url, userAgent, disposition, mime, _ ->
            host.download(this, url, userAgent, disposition, mime)
        }
        webView.setFindListener { active, count, done ->
            events("find", mapOf("active" to active, "count" to count, "done" to done))
        }
        webView.setOnLongClickListener { onLongPress() }
    }

    // ---- Commands from Dart ------------------------------------------------

    fun load(url: String) {
        val target = upgrade(untracked(url))
        applyJavaScript(target)
        webView.loadUrl(target, privacyHeaders())
    }

    fun loadInsecure(url: String) {
        Uri.parse(url).host?.let { insecureAllowed.add(it.lowercase()) }
        applyJavaScript(url)
        webView.loadUrl(url, privacyHeaders())
    }

    /** Shows [html] as if it were [baseUrl]: reader mode or a saved page. */
    fun loadHtml(html: String, baseUrl: String, reader: Boolean) {
        readerPending = reader
        webView.loadDataWithBaseURL(baseUrl, html, "text/html", "utf-8", baseUrl)
    }

    /** Brings back an unloaded tab's history and page. */
    fun restore(state: Bundle): Boolean = webView.restoreState(state) != null

    fun saveState(): Bundle = Bundle().also { webView.saveState(it) }

    fun setDesktop(on: Boolean) {
        if (desktopMode == on) return
        desktopMode = on
        applyUserAgent()
        webView.reload()
    }

    /** Text size and dark pages, after a settings change. */
    fun applyDisplay() {
        val s = webView.settings
        s.textZoom = textZoom
        if (WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
            // Darkens pages without a dark design when the phone is in dark
            // mode; pages with their own dark design use it either way.
            WebSettingsCompat.setAlgorithmicDarkeningAllowed(s, darkPages)
        }
    }

    /** Re-adds the document-start scripts after a settings or list change. */
    fun refreshScripts() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
        startScript?.remove()
        startScript = WebViewCompat.addDocumentStartJavaScript(webView, PageScripts.documentStart(), setOf("*"))
        mediaScript?.remove()
        mediaScript = if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addDocumentStartJavaScript(webView, PageScripts.media(backgroundPlay), setOf("*"))
        } else {
            null
        }
        refreshUserScripts()
    }

    // ---- User scripts (B41) ------------------------------------------------

    /** Adds the user's scripts again (they or what they store changed). */
    fun refreshUserScripts() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) return
        for (h in userScripts) h.remove()
        userScripts = UserScripts.injections(activity, isPrivate).map {
            WebViewCompat.addDocumentStartJavaScript(webView, it, setOf("*"))
        }
    }

    /**
     * Messages from user scripts (see assets/userscripts/runtime.js). The
     * site is the frame's real origin, never what the message says.
     */
    private fun listenForUserScripts() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        WebViewCompat.addWebMessageListener(webView, "ztUserScripts", setOf("*")) { _, message, origin, isMainFrame, reply ->
            val msg = try {
                JSONObject(message.data ?: return@addWebMessageListener)
            } catch (e: Exception) {
                return@addWebMessageListener
            }
            val script = UserScripts.script(msg.optString("s")) ?: return@addWebMessageListener
            if (isPrivate && !script.allowPrivate) return@addWebMessageListener
            val originHost = origin.host?.lowercase()
            when (msg.optString("t")) {
                "set" -> if (!isPrivate) UserScripts.setValue(activity, script.id, msg.optString("k"), msg.optString("v"))
                "del" -> if (!isPrivate) UserScripts.setValue(activity, script.id, msg.optString("k"), null)
                "xhr" -> UserScripts.request(msg, script, originHost, isPrivate, webView.settings.userAgentString) {
                    try { reply.postMessage(it) } catch (e: Exception) { }
                }
                "abort" -> UserScripts.abort(script.id, msg.optInt("n"))
                "tab" -> {
                    val url = msg.optString("url")
                    if (script.grants.any { it.equals("GM_openInTab", true) || it.equals("GM.openInTab", true) } &&
                        (url.startsWith("https://") || url.startsWith("http://"))
                    ) {
                        events("openTab", mapOf("url" to url, "private" to isPrivate))
                    }
                }
                "clip" -> if (script.grants.any { it.equals("GM_setClipboard", true) || it.equals("GM.setClipboard", true) }) {
                    val cm = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText(script.name, msg.optString("text")))
                }
                "notify" -> if (script.grants.any { it.equals("GM_notification", true) || it.equals("GM.notification", true) }) {
                    events(
                        "scriptNotice",
                        mapOf("script" to script.name, "title" to msg.optString("title"), "text" to msg.optString("text")),
                    )
                }
                "menu" -> if (isMainFrame) {
                    val cmds = msg.optJSONArray("cmds") ?: JSONArray()
                    if (cmds.length() == 0) scriptMenus.remove(script.id) else scriptMenus[script.id] = reply to cmds
                }
            }
        }
    }

    /** The page's user script commands: script, name, s (script id), i. */
    fun scriptCommands(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for ((id, entry) in scriptMenus) {
            val name = UserScripts.script(id)?.name ?: continue
            for (k in 0 until entry.second.length()) {
                val c = entry.second.optJSONObject(k) ?: continue
                out.add(mapOf("script" to name, "name" to c.optString("n"), "s" to id, "i" to c.optInt("i")))
            }
        }
        return out
    }

    fun runScriptCommand(scriptId: String, commandId: Int) {
        val proxy = scriptMenus[scriptId]?.first ?: return
        try {
            proxy.postMessage(JSONObject().put("t", "menu").put("s", scriptId).put("i", commandId).toString())
        } catch (e: Exception) {
            // The page is gone.
        }
    }

    /** Media events from every frame of the page (see [PageScripts.media]). */
    private fun listenForMedia() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
        WebViewCompat.addWebMessageListener(webView, "ztMedia", setOf("*")) { _, message, _, _, reply ->
            val data = message.data ?: return@addWebMessageListener
            val json = try {
                org.json.JSONObject(data)
            } catch (e: Exception) {
                return@addWebMessageListener
            }
            when (json.optString("s")) {
                "play" -> {
                    mediaFrame = reply
                    mediaPlaying = true
                    host.mediaChanged(this, true, json.optString("t").ifBlank { webView.title ?: "" })
                }
                "pause" -> if (reply == mediaFrame && mediaPlaying) {
                    mediaPlaying = false
                    host.mediaChanged(this, false, webView.title ?: "")
                }
            }
        }
    }

    /** Pauses or plays again the media that played last ("pause", "play"). */
    fun mediaControl(command: String) {
        try {
            mediaFrame?.postMessage(command)
        } catch (e: Exception) {
            // The frame is gone.
        }
    }

    /** The selected text on the page (JSON string). */
    fun selection(done: (String?) -> Unit) {
        if (!webView.settings.javaScriptEnabled) {
            done(null)
            return
        }
        webView.evaluateJavascript(PageScripts.SELECTION) { done(it) }
    }

    /** The page as a Readability article (JSON string, or "null"). */
    // ---- Translation (B16) --------------------------------------------------

    /** Names this tab's translation state on its pages. */
    private val translateKey = "__zt" + java.util.UUID.randomUUID().toString().replace("-", "").take(12)
    private var translateGen = 0
    private var translator: Translator? = null
    private var translatedFrom: String? = null
    private var translatedTo: String? = null
    private var translating = false
    private var translateDone = 0
    private var translateTotal = 0

    /** Keep translating pages of this site in this tab, as Firefox does. */
    private var keepTranslating: Triple<String, String, String>? = null

    /** The page's declared language and some of its text, as JSON. */
    fun pageLanguage(done: (String?) -> Unit) {
        if (!webView.settings.javaScriptEnabled) {
            done(null)
            return
        }
        webView.evaluateJavascript(PageScripts.PAGE_LANGUAGE) { raw -> done(decodeJsString(raw)) }
    }

    /**
     * Translates the page on the phone with [with]: the text of each block
     * goes to the translator, visible blocks first, and comes back into
     * the same text nodes (links, buttons and layout stay as they are).
     * Content added later is translated as it appears. False when the
     * page's JavaScript is off (needed to read and write its text).
     */
    fun translatePage(with: Translator, from: String, to: String): Boolean {
        if (!webView.settings.javaScriptEnabled) return false
        if (translatedTo != null) restoreText()
        val gen = ++translateGen
        translator = with
        translatedFrom = from
        translatedTo = to
        translating = true
        translateDone = 0
        translateTotal = 0
        keepTranslating = pageHost?.let { Triple(Blocker.siteOf(it), from, to) }
        sendState()
        collectMore(gen)
        return true
    }

    /** Back to the page's own text; stops translating this site. */
    fun showOriginal() {
        keepTranslating = null
        restoreText()
        sendState()
    }

    private fun restoreText() {
        translateGen++
        if (translatedTo != null) {
            webView.evaluateJavascript(PageScripts.translate(activity, translateKey) + ".restore()", null)
        }
        translatedFrom = null
        translatedTo = null
        translating = false
    }

    private fun collectMore(gen: Int) {
        val script = PageScripts.translate(activity, translateKey)
        webView.evaluateJavascript("$script.collect(400)") { raw ->
            if (gen != translateGen) return@evaluateJavascript
            val groups = try {
                JSONArray(decodeJsString(raw) ?: "[]")
            } catch (e: Exception) {
                JSONArray()
            }
            if (groups.length() == 0) {
                translating = false
                sendState()
                watchForMore(gen)
                return@evaluateJavascript
            }
            translating = true
            translateTotal += groups.length()
            queueState()
            translateChunk(gen, groups, 0)
        }
    }

    private fun translateChunk(gen: Int, groups: JSONArray, start: Int) {
        val engine = translator ?: return
        val from = translatedFrom ?: return
        val to = translatedTo ?: return
        val end = minOf(start + 12, groups.length())
        val texts = (start until end).map { groups.getJSONArray(it).getString(1) }
        engine.translate(from, to, texts, true) { out, error ->
            if (gen != translateGen) return@translate
            if (out == null || out.size != texts.size) {
                restoreText()
                keepTranslating = null
                events("translateFailed", mapOf("error" to (error ?: "failed")))
                sendState()
                return@translate
            }
            val results = JSONArray()
            for (i in out.indices) {
                results.put(JSONArray().put(groups.getJSONArray(start + i).getInt(0)).put(out[i]))
            }
            webView.evaluateJavascript(
                PageScripts.translate(activity, translateKey) + ".apply($results)",
                null,
            )
            translateDone += end - start
            queueState()
            if (end < groups.length()) translateChunk(gen, groups, end) else collectMore(gen)
        }
    }

    /** New content on a translated page (more results, comments): translate it too. */
    private fun watchForMore(gen: Int) {
        main.postDelayed({
            if (gen != translateGen) return@postDelayed
            webView.evaluateJavascript(PageScripts.translate(activity, translateKey) + ".dirty") { dirty ->
                if (gen != translateGen) return@evaluateJavascript
                if (dirty == "true") collectMore(gen) else watchForMore(gen)
            }
        }, 2500)
    }

    /** A string a script returned (evaluateJavascript gives it JSON-quoted). */
    private fun decodeJsString(raw: String?): String? =
        try {
            JSONTokener(raw ?: "null").nextValue() as? String
        } catch (e: Exception) {
            null
        }

    fun extractArticle(done: (String?) -> Unit) {
        if (!webView.settings.javaScriptEnabled) {
            done(null)
            return
        }
        webView.evaluateJavascript(PageScripts.extractArticle(activity)) { done(it) }
    }

    /**
     * Reads a blob: URL the page offered as a download, as a data: URL.
     * Null when the engine can't (old WebView) or the page refused.
     */
    fun fetchBlob(url: String, maxBytes: Long, done: (String?) -> Unit) {
        val supported = listOf(
            WebViewFeature.CREATE_WEB_MESSAGE_CHANNEL,
            WebViewFeature.POST_WEB_MESSAGE,
            WebViewFeature.WEB_MESSAGE_PORT_SET_MESSAGE_CALLBACK,
            WebViewFeature.WEB_MESSAGE_CALLBACK_ON_MESSAGE,
        ).all { WebViewFeature.isFeatureSupported(it) }
        if (!supported || !webView.settings.javaScriptEnabled) {
            done(null)
            return
        }
        val ports = WebViewCompat.createWebMessageChannel(webView)
        var answered = false
        fun finish(result: String?) {
            if (answered) return
            answered = true
            try { ports[0].close() } catch (e: Exception) { }
            done(result)
        }
        ports[0].setWebMessageCallback(object : WebMessagePortCompat.WebMessageCallbackCompat() {
            override fun onMessage(port: WebMessagePortCompat, message: WebMessageCompat?) {
                val data = message?.data
                main.post { finish(if (data != null && data.startsWith("data:")) data else null) }
            }
        })
        val key = UUID.randomUUID().toString()
        webView.evaluateJavascript(PageScripts.fetchBlob(url, key, maxBytes)) {
            WebViewCompat.postWebMessage(webView, WebMessageCompat(key, arrayOf(ports[1])), Uri.parse("*"))
        }
        main.postDelayed({ finish(null) }, 60_000)
    }

    fun destroy() {
        if (mediaFrame != null) host.mediaChanged(this, false, null)
        mediaPlaying = false
        mediaFrame = null
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.stopLoading()
        webView.destroy()
    }

    fun queueState() {
        if (stateQueued) return
        stateQueued = true
        main.postDelayed({
            stateQueued = false
            sendState()
        }, 120)
    }

    fun sendState() {
        val url = webView.url
        events(
            "state",
            mapOf(
                "url" to url,
                "title" to webView.title,
                "progress" to progress,
                "loading" to loading,
                "canGoBack" to webView.canGoBack(),
                "canGoForward" to webView.canGoForward(),
                "secure" to (url != null && url.startsWith("https://") && !sslError),
                "blocked" to blocked.get(),
                "desktop" to desktopMode,
                "readerable" to readerable,
                "reader" to inReader,
                "javascript" to webView.settings.javaScriptEnabled,
                "translatedFrom" to translatedFrom,
                "translatedTo" to translatedTo,
                "translating" to translating,
                "translateDone" to translateDone,
                "translateTotal" to translateTotal,
            ),
        )
    }

    // ---- Internals ---------------------------------------------------------

    private fun applyUserAgent() {
        webView.settings.userAgentString = if (desktopMode) desktopAgent(defaultUserAgent) else defaultUserAgent
    }

    /** JavaScript off on sites the user chose; applies from the next load. */
    private fun applyJavaScript(url: String): Boolean {
        val h = Uri.parse(url).host?.lowercase() ?: return false
        val want = Blocker.siteOf(h) !in jsOffSites
        if (webView.settings.javaScriptEnabled == want) return false
        webView.settings.javaScriptEnabled = want
        return true
    }

    private fun privacyHeaders(): Map<String, String> = mapOf("Sec-GPC" to "1", "DNT" to "1")

    /** http:// becomes https:// when HTTPS-only is on, unless allowed. */
    /**
     * [url] without tracking tags and redirect wrappers, unless the user
     * turned protection off for the site it leads to. A link this tab
     * already cleaned once during this page load is left alone, so a site
     * that keeps adding its tag back can't cause a loop.
     */
    private fun untracked(url: String): String {
        if (!LinkCleaner.enabled) return url
        val clean = LinkCleaner.clean(url)
        if (clean == url) return url
        if (Blocker.siteOf(LinkCleaner.hostOf(clean)) in Blocker.allowedSites) return url
        if (!cleaned.add(url)) return url
        if (cleaned.size > 50) cleaned.clear()
        return clean
    }

    private fun upgrade(url: String): String {
        if (!httpsOnly || !url.startsWith("http://")) return url
        val h = Uri.parse(url).host?.lowercase() ?: return url
        if (h in insecureAllowed || isLocal(h)) return url
        val https = "https://" + url.removePrefix("http://")
        upgraded[https] = url
        return https
    }

    private fun onLongPress(): Boolean {
        val hit = webView.hitTestResult
        val extra = hit.extra ?: return false
        return when (hit.type) {
            WebView.HitTestResult.SRC_ANCHOR_TYPE -> {
                events("contextMenu", mapOf("link" to extra, "image" to null))
                true
            }
            WebView.HitTestResult.IMAGE_TYPE -> {
                events("contextMenu", mapOf("link" to null, "image" to extra))
                true
            }
            WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE -> {
                // The link around the image comes back asynchronously.
                val msg = Handler(Looper.getMainLooper()) { m ->
                    events(
                        "contextMenu",
                        mapOf("link" to m.data.getString("url"), "image" to extra),
                    )
                    true
                }.obtainMessage()
                webView.requestFocusNodeHref(msg)
                true
            }
            else -> false
        }
    }

    private fun checkReaderable(view: WebView, url: String) {
        if (inReader || !view.settings.javaScriptEnabled ||
            !(url.startsWith("https://") || url.startsWith("http://"))
        ) {
            return
        }
        view.evaluateJavascript(PageScripts.readerable(activity)) { result ->
            val now = result == "true"
            if (now != readerable && view.url == url) {
                readerable = now
                queueState()
            }
        }
    }

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (!request.isForMainFrame) return false
            val url = request.url.toString()
            // B41: a link to a user script offers to install it (as
            // Tampermonkey does), instead of showing its code.
            val scheme = request.url.scheme?.lowercase()
            if ((scheme == "https" || scheme == "http") &&
                (request.url.path ?: "").lowercase().endsWith(".user.js") &&
                request.method.equals("GET", true)
            ) {
                events("userScript", mapOf("url" to url))
                return true
            }
            return when (request.url.scheme?.lowercase()) {
                "https" -> {
                    // A wrapper on https can hold an http address: that one
                    // goes through HTTPS-only like any other.
                    val target = upgrade(untracked(url))
                    applyJavaScript(target)
                    if (target == url) {
                        false
                    } else {
                        view.loadUrl(target, privacyHeaders())
                        true
                    }
                }
                "about", "data", "blob", "javascript" -> false
                "http" -> {
                    val target = upgrade(untracked(url))
                    if (target == url) {
                        applyJavaScript(url)
                        false
                    } else {
                        applyJavaScript(target)
                        view.loadUrl(target, privacyHeaders())
                        true
                    }
                }
                // mailto:, tel:, intent://, market:// ... Dart asks first.
                else -> {
                    events("external", mapOf("url" to url))
                    true
                }
            }
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            pageHost = Uri.parse(url).host
            scriptMenus.clear()
            // A new page: its translation (if any) starts again once loaded.
            translateGen++
            translatedFrom = null
            translatedTo = null
            translating = false
            // A new page: what played on the old one has stopped.
            if (mediaFrame != null) {
                mediaPlaying = false
                mediaFrame = null
                host.mediaChanged(this@ZtTab, false, null)
            }
            blocked.set(0)
            sslError = false
            loading = true
            readerable = false
            inReader = readerPending
            readerPending = false
            // Back, forward and reload skip shouldOverrideUrlLoading: catch
            // a JavaScript switch that doesn't match this site, once.
            if (!inReader && url.startsWith("http") && applyJavaScript(url) && jsReloadedFor != url) {
                jsReloadedFor = url
                view.stopLoading()
                view.reload()
            }
            queueState()
        }

        override fun onPageCommitVisible(view: WebView, url: String) {
            if (inReader) return
            Blocker.siteCss(Uri.parse(url).host)?.let { css ->
                if (view.settings.javaScriptEnabled) view.evaluateJavascript(PageScripts.siteCss(css), null)
            }
        }

        override fun onPageFinished(view: WebView, url: String) {
            loading = false
            cleaned.clear()
            sendState()
            checkReaderable(view, url)
            // Translating this site in this tab: the next page is too.
            val keep = keepTranslating
            val engine = translator
            val host = Uri.parse(url).host
            if (keep != null && engine != null && host != null && translatedTo == null) {
                if (Blocker.siteOf(host) == keep.first) {
                    translatePage(engine, keep.second, keep.third)
                } else {
                    keepTranslating = null
                }
            }
            if (!isPrivate && !inReader && (url.startsWith("http://") || url.startsWith("https://"))) {
                events("visited", mapOf("url" to url, "title" to view.title))
            }
        }

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
            pageHost = Uri.parse(url).host
            queueState()
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            if (request.isForMainFrame) return null
            if (Blocker.shouldBlock(request.url.host, pageHost)) {
                blocked.incrementAndGet()
                main.post { queueState() }
                return WebResourceResponse("text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(ByteArray(0)))
            }
            return null
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (!request.isForMainFrame) return
            val url = request.url.toString()
            val insecure = upgraded.remove(url)
            if (insecure != null) {
                events("httpsFailed", mapOf("url" to insecure))
            }
        }

        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
            // Never proceed past a bad certificate.
            sslError = true
            handler.cancel()
            events("sslError", mapOf("url" to error.url))
            queueState()
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            host.onCrashed(this@ZtTab)
            return true
        }
    }

    private inner class Chrome : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress = newProgress
            queueState()
        }

        override fun onReceivedTitle(view: WebView, title: String?) = queueState()

        override fun onReceivedIcon(view: WebView, icon: Bitmap) {
            val size = 64
            val scaled = Bitmap.createScaledBitmap(icon, size, size, true)
            val out = ByteArrayOutputStream()
            scaled.compress(Bitmap.CompressFormat.PNG, 100, out)
            events("favicon", mapOf("png" to out.toByteArray()))
        }

        override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
            // Pop-ups only on a tap; they open as a new tab.
            if (!isUserGesture) return false
            val catcher = WebView(activity)
            if (isPrivate && privateProfileSupported()) {
                WebViewCompat.setProfile(catcher, PRIVATE_PROFILE)
            }
            catcher.webViewClient = object : WebViewClient() {
                private var sent = false

                private fun open(url: String) {
                    if (sent) return
                    sent = true
                    events("openTab", mapOf("url" to url, "private" to isPrivate))
                    main.post { catcher.destroy() }
                }

                override fun shouldOverrideUrlLoading(v: WebView, request: WebResourceRequest): Boolean {
                    open(request.url.toString())
                    return true
                }

                override fun onPageStarted(v: WebView, url: String, favicon: Bitmap?) {
                    if (url != "about:blank") {
                        v.stopLoading()
                        open(url)
                    }
                }
            }
            (resultMsg.obj as WebView.WebViewTransport).webView = catcher
            resultMsg.sendToTarget()
            return true
        }

        override fun onShowFileChooser(
            webView: WebView,
            filePathCallback: ValueCallback<Array<Uri>>,
            fileChooserParams: FileChooserParams,
        ): Boolean = host.showFileChooser(filePathCallback, fileChooserParams)

        override fun onShowCustomView(view: View, callback: CustomViewCallback) {
            host.showFullscreen(view) { callback.onCustomViewHidden() }
        }

        override fun onHideCustomView() = host.hideFullscreen()

        /** Camera and microphone: asked per site; anything else refused. */
        override fun onPermissionRequest(request: PermissionRequest) {
            val kinds = ArrayList<String>()
            for (r in request.resources) {
                when (r) {
                    PermissionRequest.RESOURCE_VIDEO_CAPTURE -> kinds.add("camera")
                    PermissionRequest.RESOURCE_AUDIO_CAPTURE -> kinds.add("microphone")
                    else -> {
                        request.deny()
                        return
                    }
                }
            }
            if (kinds.isEmpty()) {
                request.deny()
                return
            }
            host.askPermission(this@ZtTab, request.origin.toString(), kinds) { allowed ->
                val grant = ArrayList<String>()
                if ("camera" in allowed) grant.add(PermissionRequest.RESOURCE_VIDEO_CAPTURE)
                if ("microphone" in allowed) grant.add(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                try {
                    if (grant.size == kinds.size) request.grant(grant.toTypedArray()) else request.deny()
                } catch (e: IllegalStateException) {
                    // The page gave up waiting.
                }
            }
        }

        override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
            host.askPermission(this@ZtTab, origin, listOf("location")) { allowed ->
                // Not retained by the engine: Dart remembers the answer.
                callback.invoke(origin, "location" in allowed, false)
            }
        }
    }

    companion object {
        const val PRIVATE_PROFILE = "zt-private"

        /** HTTPS-only mode, pushed from Dart (`setPrivacy`). */
        @Volatile var httpsOnly = true

        /** Sites (registrable domains) where JavaScript is off. */
        @Volatile var jsOffSites: Set<String> = emptySet()

        /** Keep media playing in the background (B26), pushed from Dart. */
        @Volatile var backgroundPlay = true

        /** Page text size in percent, and dark pages; pushed from Dart. */
        @Volatile var textZoom = 100
        @Volatile var darkPages = true

        fun privateProfileSupported(): Boolean =
            WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

        private fun isLocal(host: String) =
            host == "localhost" || host.endsWith(".local") || host.startsWith("192.168.") ||
                host.startsWith("10.") || host == "127.0.0.1"

        private fun desktopAgent(mobile: String): String {
            val chrome = Regex("Chrome/[\\d.]+").find(mobile)?.value ?: "Chrome/130.0.0.0"
            return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) $chrome Safari/537.36"
        }
    }
}
