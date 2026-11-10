package dev.sagron.zerotrustbrowser

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.net.http.SslError
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
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicInteger

/**
 * One browser tab: a WebView that outlives the Flutter widget showing it,
 * so switching tabs or locking the app keeps the page as it was. Dart
 * closes it with `closeTab`.
 *
 * Privacy defaults: trackers blocked ([Blocker]), third-party cookies off,
 * no file or content access, no mixed content, popups only on a tap, every
 * site permission (camera, microphone, location) refused, Global Privacy
 * Control sent. Private tabs use their own WebView profile (cookies,
 * storage, cache), removed when the last private tab closes.
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
    }

    val webView: WebView = WebView(activity)
    private val main = Handler(Looper.getMainLooper())
    private val blocked = AtomicInteger(0)
    private val defaultUserAgent: String

    /** Host of the page now showing, read by the network thread. */
    @Volatile private var pageHost: String? = null

    /** http:// URLs this tab upgraded to https, to explain a failure. */
    private val upgraded = HashMap<String, String>()

    /** Hosts the user agreed to load over plain http in this tab. */
    private val insecureAllowed = HashSet<String>()
    private var stateQueued = false
    private var progress = 0
    private var loading = false
    private var sslError = false
    private var desktopMode = desktop

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
        s.setGeolocationEnabled(false)
        if (isPrivate) {
            @Suppress("DEPRECATION")
            s.saveFormData = false
            // Without its own profile, at least nothing is kept in the cache.
            if (!privateProfileSupported()) s.cacheMode = WebSettings.LOAD_NO_CACHE
        }
        // Look like Chrome rather than an in-app WebView ("; wv" makes some
        // sign-in pages refuse), and keep the original for desktop mode.
        defaultUserAgent = s.userAgentString
            .replace("; wv)", ")")
            .replace(Regex("Version/\\d+\\.\\d+ "), "")
        applyUserAgent()
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(webView, GPC_SCRIPT, setOf("*"))
        }
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
        val target = upgrade(url)
        webView.loadUrl(target, privacyHeaders())
    }

    fun loadInsecure(url: String) {
        Uri.parse(url).host?.let { insecureAllowed.add(it.lowercase()) }
        webView.loadUrl(url, privacyHeaders())
    }

    fun setDesktop(on: Boolean) {
        if (desktopMode == on) return
        desktopMode = on
        applyUserAgent()
        webView.reload()
    }

    fun destroy() {
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
            ),
        )
    }

    // ---- Internals ---------------------------------------------------------

    private fun applyUserAgent() {
        webView.settings.userAgentString = if (desktopMode) desktopAgent(defaultUserAgent) else defaultUserAgent
    }

    private fun privacyHeaders(): Map<String, String> = mapOf("Sec-GPC" to "1", "DNT" to "1")

    /** http:// becomes https:// when HTTPS-only is on, unless allowed. */
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

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (!request.isForMainFrame) return false
            val url = request.url.toString()
            return when (request.url.scheme?.lowercase()) {
                "https", "about", "data", "blob", "javascript" -> false
                "http" -> {
                    val target = upgrade(url)
                    if (target == url) {
                        false
                    } else {
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
            blocked.set(0)
            sslError = false
            loading = true
            queueState()
        }

        override fun onPageFinished(view: WebView, url: String) {
            loading = false
            sendState()
            if (!isPrivate && (url.startsWith("http://") || url.startsWith("https://"))) {
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

        override fun onPermissionRequest(request: PermissionRequest) = request.deny()

        override fun onGeolocationPermissionsShowPrompt(origin: String, callback: GeolocationPermissions.Callback) {
            callback.invoke(origin, false, false)
        }
    }

    companion object {
        const val PRIVATE_PROFILE = "zt-private"

        /** HTTPS-only mode, pushed from Dart (`setPrivacy`). */
        @Volatile var httpsOnly = true

        fun privateProfileSupported(): Boolean =
            WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

        private fun isLocal(host: String) =
            host == "localhost" || host.endsWith(".local") || host.startsWith("192.168.") ||
                host.startsWith("10.") || host == "127.0.0.1"

        /** Tells sites the user opts out of sale and sharing (Global Privacy Control). */
        private const val GPC_SCRIPT =
            "try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl'," +
                "{get:function(){return true},configurable:true})}catch(e){}"

        private fun desktopAgent(mobile: String): String {
            val chrome = Regex("Chrome/[\\d.]+").find(mobile)?.value ?: "Chrome/130.0.0.0"
            return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) $chrome Safari/537.36"
        }
    }
}
