package dev.sagron.zerotrustbrowser

import android.Manifest
import android.app.DownloadManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.Settings
import android.speech.RecognizerIntent
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.autofill.AutofillManager
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebStorage
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import com.google.zxing.integration.android.IntentIntegrator
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * The browser shell. Tabs ([ZtTab]) live here, keyed by the id Dart gives
 * them, and are shown through the `zt_browser/tab` platform view. Everything
 * else goes over the `zt_browser/engine` channel: tab commands from Dart,
 * tab events (state, favicon, downloads, links) back to Dart.
 */
class MainActivity : FlutterFragmentActivity(), ZtTab.TabHost {
    private var channel: MethodChannel? = null
    private val tabs = HashMap<String, ZtTab>()
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    /** A link from another app (VIEW, web search, shared text), until Dart takes it. */
    private var pendingUrl: String? = null
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var fullscreenView: View? = null
    private var fullscreenHidden: (() -> Unit)? = null

    /** Tabs unloaded to save memory: their history, to restore on return. */
    private val savedStates = HashMap<String, Bundle>()
    private val lastUsed = HashMap<String, Long>()
    private var currentTab: String? = null

    /** Site permission questions waiting for the user (Dart). */
    private val asks = HashMap<Int, Pair<List<String>, (Set<String>) -> Unit>>()
    private var nextAsk = 1
    private var runtimeAsk: Pair<Set<String>, (Set<String>) -> Unit>? = null

    /** Dart calls waiting for another app or screen (QR, voice, file). */
    private val waiting = HashMap<Int, MethodChannel.Result>()

    private lateinit var downloads: Downloads

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        downloads = Downloads(this)
        pendingUrl = linkFrom(intent)
        Blocker.onLoaded = {
            PageScripts.invalidate()
            for (t in tabs.values) t.refreshScripts()
        }
        Blocker.load(this)
        // A private profile left over from a crash: nothing may survive it.
        deletePrivateProfileIfUnused()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingUrl = linkFrom(intent) ?: return
        channel?.invokeMethod("openPending", null)
    }

    private fun linkFrom(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_WEB_SEARCH -> intent.getStringExtra("query")
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zt_browser/engine")
        channel = ch
        flutterEngine.platformViewsController.registry
            .registerViewFactory("zt_browser/tab", TabViewFactory())
        ch.setMethodCallHandler { call, result ->
            try {
                val tabId = call.argument<String>("tabId")
                val tab = tabId?.let { tabs[it] }
                when (call.method) {
                    "consumePending" -> {
                        result.success(pendingUrl)
                        pendingUrl = null
                    }
                    "createTab" -> {
                        if (tabId != null && tab == null) {
                            val t = ZtTab(
                                this, tabId,
                                isPrivate = call.argument<Boolean>("private") ?: false,
                                desktop = call.argument<Boolean>("desktop") ?: false,
                                events = { type, data -> tabEvent(tabId, type, data) },
                                host = this,
                            )
                            tabs[tabId] = t
                            lastUsed[tabId] = System.currentTimeMillis()
                            val saved = savedStates.remove(tabId)
                            if (saved == null || !t.restore(saved)) {
                                call.argument<String>("url")?.let { t.load(it) }
                            }
                        }
                        result.success(null)
                    }
                    "closeTab" -> {
                        if (tab != null) {
                            tabs.remove(tabId)
                            tab.destroy()
                        }
                        savedStates.remove(tabId)
                        lastUsed.remove(tabId)
                        // Also after a crash, when the WebView is already gone.
                        deletePrivateProfileIfUnused()
                        result.success(null)
                    }
                    "select" -> {
                        currentTab = tabId
                        if (tabId != null) lastUsed[tabId] = System.currentTimeMillis()
                        unloadOldTabs(MAX_LIVE_TABS)
                        result.success(null)
                    }
                    "exitFullscreen" -> {
                        hideFullscreen()
                        result.success(null)
                    }
                    "load" -> { tab?.load(call.argument<String>("url") ?: ""); result.success(null) }
                    "loadInsecure" -> { tab?.loadInsecure(call.argument<String>("url") ?: ""); result.success(null) }
                    "loadHtml" -> {
                        tab?.loadHtml(
                            call.argument<String>("html") ?: "",
                            call.argument<String>("baseUrl") ?: "about:blank",
                            call.argument<Boolean>("reader") ?: false,
                        )
                        result.success(null)
                    }
                    "article" -> {
                        if (tab == null) result.success(null) else tab.extractArticle { result.success(it) }
                    }
                    "back" -> { tab?.webView?.goBack(); result.success(null) }
                    "forward" -> { tab?.webView?.goForward(); result.success(null) }
                    "reload" -> { tab?.webView?.reload(); result.success(null) }
                    "stop" -> { tab?.webView?.stopLoading(); result.success(null) }
                    "setDesktop" -> { tab?.setDesktop(call.argument<Boolean>("on") ?: false); result.success(null) }
                    "find" -> {
                        tab?.webView?.findAllAsync(call.argument<String>("text") ?: "")
                        result.success(null)
                    }
                    "findNext" -> {
                        tab?.webView?.findNext(call.argument<Boolean>("forward") ?: true)
                        result.success(null)
                    }
                    "clearFind" -> { tab?.webView?.clearMatches(); result.success(null) }
                    "state" -> { tab?.sendState(); result.success(null) }
                    "setPrivacy" -> {
                        Blocker.enabled = call.argument<Boolean>("blockTrackers") ?: true
                        Blocker.hideElements = call.argument<Boolean>("hideElements") ?: true
                        Blocker.allowedSites = sites(call.argument<List<String>>("allowedSites"))
                        ZtTab.httpsOnly = call.argument<Boolean>("httpsOnly") ?: true
                        ZtTab.jsOffSites = sites(call.argument<List<String>>("javascriptOff"))
                        PageScripts.fingerprinting = call.argument<Boolean>("fingerprinting") ?: true
                        PageScripts.invalidate()
                        for (t in tabs.values) t.refreshScripts()
                        result.success(null)
                    }
                    "setDisplay" -> {
                        ZtTab.textZoom = call.argument<Int>("textZoom") ?: 100
                        ZtTab.darkPages = call.argument<Boolean>("darkPages") ?: true
                        for (t in tabs.values) t.applyDisplay()
                        result.success(null)
                    }
                    "siteOf" -> result.success(Blocker.siteOf((call.argument<String>("host") ?: "").lowercase()))
                    "blocklistSize" -> result.success(Blocker.size())
                    "blocklistInfo" -> result.success(
                        mapOf(
                            "size" to Blocker.size(),
                            "date" to Blocker.listDate,
                            "updated" to Blocker.fromUpdate,
                            "file" to Blocker.updateFile(this).absolutePath,
                        ),
                    )
                    "reloadBlocklist" -> {
                        Blocker.reload(this)
                        result.success(null)
                    }
                    "privateProfileSupported" -> result.success(ZtTab.privateProfileSupported())
                    "clearBrowsingData" -> {
                        clearBrowsingData()
                        result.success(null)
                    }
                    "answerPermission" -> {
                        answerPermission(
                            call.argument<Int>("requestId") ?: 0,
                            (call.argument<List<String>>("allowed") ?: emptyList()).toSet(),
                        )
                        result.success(null)
                    }
                    "openExternal" -> result.success(openExternal(call.argument<String>("url") ?: ""))
                    "isDefaultBrowser" -> result.success(isDefaultBrowser())
                    "openDefaultBrowserSettings" -> {
                        openDefaultBrowserSettings()
                        result.success(null)
                    }
                    "downloads" -> result.success(downloads.list())
                    "openDownload" -> result.success(downloads.open(call.argument<String>("key") ?: ""))
                    "shareDownload" -> result.success(downloads.share(call.argument<String>("key") ?: ""))
                    "deleteDownload" -> {
                        downloads.delete(call.argument<String>("key") ?: "")
                        result.success(null)
                    }
                    "print" -> {
                        if (tab != null) printPage(tab, call.argument<String>("title"))
                        result.success(null)
                    }
                    "addShortcut" -> result.success(
                        addShortcut(
                            call.argument<String>("url") ?: "",
                            call.argument<String>("title") ?: "",
                            call.argument<ByteArray>("icon"),
                        ),
                    )
                    "pickFile" -> pickFile(call.argument<List<String>>("mimeTypes") ?: listOf("*/*"), result)
                    "scanQr" -> scanQr(result)
                    "voiceAvailable" -> result.success(voiceIntent().resolveActivity(packageManager) != null)
                    "voiceSearch" -> voiceSearch(result)
                    "autofillStatus" -> result.success(autofillStatus())
                    "openAutofillSettings" -> {
                        openAutofillSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }

    private fun sites(list: List<String>?): Set<String> =
        (list ?: emptyList()).map { Blocker.siteOf(it.lowercase()) }.toSet()

    private fun tabEvent(tabId: String, type: String, data: Map<String, Any?>) {
        channel?.invokeMethod("tabEvent", HashMap(data).apply {
            put("tabId", tabId)
            put("type", type)
        })
    }

    /** Another app or screen is on top: auto-lock waits for it. */
    private fun systemUi(open: Boolean) {
        channel?.invokeMethod("systemUi", open)
    }

    // ---- Platform view ----------------------------------------------------

    /** Shows an existing tab's WebView; disposing the view keeps the tab. */
    private inner class TabViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val tabId = (args as? Map<*, *>)?.get("tabId") as? String
            val tab = tabId?.let { tabs[it] }
            val view: View = tab?.webView?.also { (it.parent as? ViewGroup)?.removeView(it) }
                ?: View(context).apply { setBackgroundColor(Color.TRANSPARENT) }
            return object : PlatformView {
                override fun getView(): View = view
                override fun dispose() {
                    (view.parent as? ViewGroup)?.removeView(view)
                }
            }
        }
    }

    // ---- Memory -------------------------------------------------------------

    /**
     * Keeps at most [keep] normal tabs alive; the least recently used others
     * are unloaded, keeping their history, and reload when shown again.
     * Private tabs are never unloaded: that would lose them for good.
     */
    private fun unloadOldTabs(keep: Int) {
        if (fullscreenView != null) return
        val normal = tabs.values.filter { !it.isPrivate }
        val extra = normal.size - keep
        if (extra <= 0) return
        normal.filter { it.id != currentTab }
            .sortedBy { lastUsed[it.id] ?: 0L }
            .take(extra)
            .forEach { unload(it) }
    }

    private fun unload(tab: ZtTab) {
        try {
            savedStates[tab.id] = tab.saveState()
        } catch (e: Exception) {
            // Without history it still reloads its address.
        }
        tabs.remove(tab.id)
        tab.destroy()
        tabEvent(tab.id, "unloaded", emptyMap())
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        @Suppress("DEPRECATION")
        val low = level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
            level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND
        if (low) unloadOldTabs(1)
    }

    // ---- Tab host ---------------------------------------------------------

    override fun showFileChooser(
        callback: ValueCallback<Array<Uri>>,
        params: WebChromeClient.FileChooserParams,
    ): Boolean {
        fileCallback?.onReceiveValue(null)
        fileCallback = callback
        return try {
            @Suppress("DEPRECATION")
            startActivityForResult(params.createIntent(), REQUEST_FILE)
            systemUi(true)
            true
        } catch (e: ActivityNotFoundException) {
            fileCallback = null
            false
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_FILE -> {
                fileCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
                fileCallback = null
                systemUi(false)
            }
            REQUEST_PICK -> {
                systemUi(false)
                val result = waiting.remove(REQUEST_PICK) ?: return
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                io.execute {
                    val bytes = try {
                        contentResolver.openInputStream(uri)?.use { input ->
                            val out = java.io.ByteArrayOutputStream()
                            val buf = ByteArray(64 * 1024)
                            var total = 0
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                total += n
                                if (total > MAX_PICKED_BYTES) throw IllegalStateException("too large")
                                out.write(buf, 0, n)
                            }
                            out.toByteArray()
                        }
                    } catch (e: Exception) {
                        null
                    }
                    main.post { result.success(bytes) }
                }
            }
            REQUEST_QR -> {
                systemUi(false)
                val text = IntentIntegrator.parseActivityResult(resultCode, data)?.contents
                waiting.remove(REQUEST_QR)?.success(text)
            }
            REQUEST_VOICE -> {
                systemUi(false)
                val text = if (resultCode == RESULT_OK) {
                    data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
                } else {
                    null
                }
                waiting.remove(REQUEST_VOICE)?.success(text)
            }
        }
    }

    override fun showFullscreen(view: View, onHidden: () -> Unit) {
        hideFullscreen()
        fullscreenView = view
        fullscreenHidden = onHidden
        (window.decorView as FrameLayout).addView(
            view,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT),
        )
        setSystemBars(visible = false)
    }

    override fun hideFullscreen() {
        val v = fullscreenView ?: return
        fullscreenView = null
        (window.decorView as FrameLayout).removeView(v)
        setSystemBars(visible = true)
        fullscreenHidden?.invoke()
        fullscreenHidden = null
    }

    @Suppress("DEPRECATION")
    private fun setSystemBars(visible: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val c = window.insetsController ?: return
            if (visible) {
                c.show(WindowInsets.Type.systemBars())
            } else {
                c.hide(WindowInsets.Type.systemBars())
                c.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            window.decorView.systemUiVisibility = if (visible) {
                View.SYSTEM_UI_FLAG_VISIBLE
            } else {
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (fullscreenView != null) {
            hideFullscreen()
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    override fun download(tab: ZtTab, url: String, userAgent: String, disposition: String?, mime: String?) {
        val name = URLUtil.guessFileName(url, disposition, mime)
        when {
            url.startsWith("data:") -> saveDataUrl(tab, url, disposition)
            url.startsWith("blob:") -> {
                val named = Downloads.withExtension(name, mime)
                tabEvent(tab.id, "download", mapOf("name" to named, "started" to true))
                tab.fetchBlob(url, MAX_INLINE_BYTES) { dataUrl ->
                    if (dataUrl == null) {
                        tabEvent(tab.id, "downloadDone", mapOf("name" to named, "ok" to false))
                    } else {
                        saveDataUrl(tab, dataUrl, disposition, fallbackName = named, announce = false)
                    }
                }
            }
            url.startsWith("http://") || url.startsWith("https://") -> {
                val request = DownloadManager.Request(Uri.parse(url))
                    .setMimeType(mime)
                    .addRequestHeader("User-Agent", userAgent)
                    .setTitle(name)
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
                // Each tab's own cookies: a private tab's come from its profile,
                // never from normal tabs.
                cookieManagerFor(tab).getCookie(url)?.let { request.addRequestHeader("Cookie", it) }
                val id = getSystemService(DownloadManager::class.java)?.enqueue(request)
                if (id != null) downloads.addManaged(id, name, mime)
                tabEvent(tab.id, "download", mapOf("name" to name, "started" to (id != null)))
            }
            else -> tabEvent(tab.id, "download", mapOf("name" to name, "started" to false))
        }
    }

    /** A data: URL (or a blob: read back as one) saved to Downloads. */
    private fun saveDataUrl(
        tab: ZtTab,
        url: String,
        disposition: String?,
        fallbackName: String? = null,
        announce: Boolean = true,
    ) {
        val head = url.substring(0, minOf(url.length, 200))
        val mime = head.removePrefix("data:").substringBefore(',').substringBefore(';').ifEmpty { "text/plain" }
        val name = Downloads.withExtension(fallbackName ?: URLUtil.guessFileName(head, disposition, mime), mime)
        if (announce) tabEvent(tab.id, "download", mapOf("name" to name, "started" to true))
        io.execute {
            val ok = try {
                val bytes = Downloads.decodeDataUrl(url)
                bytes != null && bytes.size <= MAX_INLINE_BYTES && downloads.saveBytes(bytes, name, mime)
            } catch (e: Exception) {
                false
            }
            main.post { tabEvent(tab.id, "downloadDone", mapOf("name" to name, "ok" to ok)) }
        }
    }

    private fun cookieManagerFor(tab: ZtTab): CookieManager =
        if (tab.isPrivate && ZtTab.privateProfileSupported()) {
            WebViewCompat.getProfile(tab.webView).cookieManager
        } else {
            CookieManager.getInstance()
        }

    override fun onCrashed(tab: ZtTab) {
        tabs.remove(tab.id)
        tab.destroy()
        tabEvent(tab.id, "crashed", emptyMap())
    }

    // ---- Site permissions ---------------------------------------------------

    override fun askPermission(tab: ZtTab, origin: String, kinds: List<String>, answer: (Set<String>) -> Unit) {
        val id = nextAsk++
        asks[id] = kinds to answer
        tabEvent(
            tab.id,
            "permission",
            mapOf("requestId" to id, "origin" to origin, "kinds" to kinds, "private" to tab.isPrivate),
        )
    }

    /** The user's answer; Android's own permission is asked next if needed. */
    private fun answerPermission(requestId: Int, allowed: Set<String>) {
        val (kinds, answer) = asks.remove(requestId) ?: return
        val wanted = kinds.filter { it in allowed }.toSet()
        val missing = wanted.flatMap { androidPermissions(it) }
            .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (wanted.isEmpty() || missing.isEmpty() || runtimeAsk != null) {
            answer(wanted.filter { hasAndroidPermission(it) }.toSet())
            return
        }
        runtimeAsk = wanted to answer
        systemUi(true)
        requestPermissions(missing.distinct().toTypedArray(), REQUEST_PERMISSIONS)
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSIONS) return
        systemUi(false)
        val (wanted, answer) = runtimeAsk ?: return
        runtimeAsk = null
        answer(wanted.filter { hasAndroidPermission(it) }.toSet())
    }

    private fun androidPermissions(kind: String): List<String> = when (kind) {
        "camera" -> listOf(Manifest.permission.CAMERA)
        "microphone" -> listOf(Manifest.permission.RECORD_AUDIO)
        "location" -> listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        else -> emptyList()
    }

    private fun hasAndroidPermission(kind: String): Boolean {
        val needed = androidPermissions(kind)
        if (needed.isEmpty()) return false
        // Location: approximate is enough.
        return if (kind == "location") {
            needed.any { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        } else {
            needed.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        }
    }

    // ---- Print, shortcuts, files, QR, voice, autofill -------------------------

    private fun printPage(tab: ZtTab, title: String?) {
        val name = title?.takeIf { it.isNotBlank() } ?: "Web page"
        val manager = getSystemService(PrintManager::class.java) ?: return
        val adapter = TrackedPrintAdapter(tab.webView.createPrintDocumentAdapter(name)) { systemUi(false) }
        systemUi(true)
        manager.print(name, adapter, PrintAttributes.Builder().build())
    }

    /** Pins a home screen shortcut that opens [url] in ZT Browser. */
    private fun addShortcut(url: String, title: String, iconPng: ByteArray?): Boolean {
        val manager = getSystemService(ShortcutManager::class.java) ?: return false
        if (!manager.isRequestPinShortcutSupported) return false
        val label = title.ifBlank { Uri.parse(url).host ?: url }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).setClass(this, MainActivity::class.java)
        val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
        val id = "site-" + digest.take(12).joinToString("") { "%02x".format(it) }
        val info = ShortcutInfo.Builder(this, id)
            .setShortLabel(label.take(24))
            .setLongLabel(label.take(48))
            .setIcon(Icon.createWithAdaptiveBitmap(shortcutIcon(iconPng, label)))
            .setIntent(intent)
            .build()
        return manager.requestPinShortcut(info, null)
    }

    /** The site's icon on a light background, or its first letter. */
    private fun shortcutIcon(png: ByteArray?, label: String): Bitmap {
        val size = 216 // 108 dp at 2x: an adaptive icon's full canvas.
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(Color.rgb(0xF5, 0xF5, 0xF4))
        val favicon = png?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        if (favicon != null) {
            val inner = 88
            val left = (size - inner) / 2
            canvas.drawBitmap(
                favicon,
                null,
                Rect(left, left, left + inner, left + inner),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
        } else {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.rgb(0xF9, 0x73, 0x16)
                textSize = 96f
                textAlign = Paint.Align.CENTER
                isFakeBoldText = true
            }
            val letter = label.trim().firstOrNull()?.uppercase() ?: "?"
            canvas.drawText(letter, size / 2f, size / 2f - (paint.descent() + paint.ascent()) / 2, paint)
        }
        return bmp
    }

    private fun pickFile(mimeTypes: List<String>, result: MethodChannel.Result) {
        waiting.remove(REQUEST_PICK)?.success(null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(if (mimeTypes.size == 1) mimeTypes[0] else "*/*")
        if (mimeTypes.size > 1) intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
        try {
            waiting[REQUEST_PICK] = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_PICK)
            systemUi(true)
        } catch (e: ActivityNotFoundException) {
            waiting.remove(REQUEST_PICK)
            result.success(null)
        }
    }

    private fun scanQr(result: MethodChannel.Result) {
        waiting.remove(REQUEST_QR)?.success(null)
        waiting[REQUEST_QR] = result
        systemUi(true)
        IntentIntegrator(this)
            .setDesiredBarcodeFormats(IntentIntegrator.QR_CODE)
            .setPrompt("Point at a QR code")
            .setBeepEnabled(false)
            .setOrientationLocked(false)
            .setRequestCode(REQUEST_QR)
            .initiateScan()
    }

    private fun voiceIntent(): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
        .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        .putExtra(RecognizerIntent.EXTRA_PROMPT, "Search or say an address")

    private fun voiceSearch(result: MethodChannel.Result) {
        waiting.remove(REQUEST_VOICE)?.success(null)
        try {
            waiting[REQUEST_VOICE] = result
            @Suppress("DEPRECATION")
            startActivityForResult(voiceIntent(), REQUEST_VOICE)
            systemUi(true)
        } catch (e: ActivityNotFoundException) {
            waiting.remove(REQUEST_VOICE)
            result.success(null)
        }
    }

    /** Which password manager fills forms (Android autofill), if any. */
    private fun autofillStatus(): Map<String, Any?> {
        val manager = getSystemService(AutofillManager::class.java)
        val supported = manager?.isAutofillSupported == true
        val component = if (supported && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager?.autofillServiceComponentName
        } else {
            null
        }
        val label = component?.let {
            try {
                packageManager.getApplicationInfo(it.packageName, 0).loadLabel(packageManager).toString()
            } catch (e: Exception) {
                it.packageName
            }
        }
        return mapOf("supported" to supported, "enabled" to (manager?.isEnabled == true), "service" to label)
    }

    private fun openAutofillSettings() {
        // Android 14+: "Passwords, passkeys & accounts"; earlier, the
        // general settings (the autofill choice is under System there).
        val candidates = listOf(
            Intent("android.settings.CREDENTIAL_PROVIDER"),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (intent in candidates) {
            try {
                startActivity(intent)
                return
            } catch (e: ActivityNotFoundException) {
                // Try the next one.
            }
        }
    }

    // ---- Engine ----------------------------------------------------------

    private fun deletePrivateProfileIfUnused() {
        if (!ZtTab.privateProfileSupported()) return
        if (tabs.values.any { it.isPrivate }) return
        try {
            val store = ProfileStore.getInstance()
            if (store.getProfile(ZtTab.PRIVATE_PROFILE) != null) {
                store.deleteProfile(ZtTab.PRIVATE_PROFILE)
            }
        } catch (e: Exception) {
            // Still in use by a WebView being torn down; removed next start.
        }
    }

    /** Cookies, site storage and cache of normal tabs, and unloaded tabs' history. */
    private fun clearBrowsingData() {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebStorage.getInstance().deleteAllData()
        savedStates.clear()
        val anyTab = tabs.values.firstOrNull { !it.isPrivate }?.webView
        if (anyTab != null) {
            anyTab.clearCache(true)
        } else {
            WebView(this).apply {
                clearCache(true)
                destroy()
            }
        }
    }

    /**
     * Opens mailto:, tel:, intent:// and other app links after the user
     * agreed. Returns a web fallback URL to load instead, if the app is
     * missing and the link has one.
     */
    private fun openExternal(url: String): String? {
        val intent = try {
            if (url.startsWith("intent:")) Intent.parseUri(url, Intent.URI_INTENT_SCHEME) else Intent(Intent.ACTION_VIEW, Uri.parse(url))
        } catch (e: Exception) {
            return null
        }
        // A web page must not reach a specific non-exported component.
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        return try {
            startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            intent.getStringExtra("browser_fallback_url")
        }
    }

    private fun isDefaultBrowser(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return getSystemService(RoleManager::class.java)?.isRoleHeld(RoleManager.ROLE_BROWSER) == true
        }
        return false
    }

    private fun openDefaultBrowserSettings() {
        val roles = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) getSystemService(RoleManager::class.java) else null
        if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_BROWSER) && !roles.isRoleHeld(RoleManager.ROLE_BROWSER)) {
            @Suppress("DEPRECATION")
            startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_BROWSER), REQUEST_ROLE)
            return
        }
        startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
    }

    override fun onDestroy() {
        for (t in tabs.values) t.destroy()
        tabs.clear()
        deletePrivateProfileIfUnused()
        Blocker.onLoaded = null
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_FILE = 4101
        private const val REQUEST_ROLE = 4102
        private const val REQUEST_PERMISSIONS = 4103
        private const val REQUEST_PICK = 4104
        private const val REQUEST_QR = 4105
        private const val REQUEST_VOICE = 4106

        /** Normal tabs kept loaded; older ones unload until shown again. */
        private const val MAX_LIVE_TABS = 5
        private const val MAX_PICKED_BYTES = 20 * 1024 * 1024

        /** data: and blob: downloads go through memory, so they're capped. */
        const val MAX_INLINE_BYTES = 50L * 1024 * 1024
    }
}
