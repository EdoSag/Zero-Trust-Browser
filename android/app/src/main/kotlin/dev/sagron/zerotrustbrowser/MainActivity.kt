package dev.sagron.zerotrustbrowser

import android.app.DownloadManager
import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.webkit.CookieManager
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebStorage
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.webkit.ProfileStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The browser shell. Tabs ([ZtTab]) live here, keyed by the id Dart gives
 * them, and are shown through the `zt_browser/tab` platform view. Everything
 * else goes over the `zt_browser/engine` channel: tab commands from Dart,
 * tab events (state, favicon, downloads, links) back to Dart.
 */
class MainActivity : FlutterFragmentActivity(), ZtTab.TabHost {
    private var channel: MethodChannel? = null
    private val tabs = HashMap<String, ZtTab>()

    /** A link from another app (VIEW, web search, shared text), until Dart takes it. */
    private var pendingUrl: String? = null
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var fullscreenView: View? = null
    private var fullscreenHidden: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingUrl = linkFrom(intent)
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
                            call.argument<String>("url")?.let { t.load(it) }
                        }
                        result.success(null)
                    }
                    "closeTab" -> {
                        if (tab != null) {
                            tabs.remove(tabId)
                            tab.destroy()
                            if (tab.isPrivate) deletePrivateProfileIfUnused()
                        }
                        result.success(null)
                    }
                    "load" -> { tab?.load(call.argument<String>("url") ?: ""); result.success(null) }
                    "loadInsecure" -> { tab?.loadInsecure(call.argument<String>("url") ?: ""); result.success(null) }
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
                        Blocker.allowedSites = (call.argument<List<String>>("allowedSites") ?: emptyList())
                            .map { Blocker.siteOf(it.lowercase()) }.toSet()
                        ZtTab.httpsOnly = call.argument<Boolean>("httpsOnly") ?: true
                        result.success(null)
                    }
                    "siteOf" -> result.success(Blocker.siteOf((call.argument<String>("host") ?: "").lowercase()))
                    "blocklistSize" -> result.success(Blocker.size())
                    "privateProfileSupported" -> result.success(ZtTab.privateProfileSupported())
                    "clearBrowsingData" -> {
                        clearBrowsingData()
                        result.success(null)
                    }
                    "openExternal" -> result.success(openExternal(call.argument<String>("url") ?: ""))
                    "isDefaultBrowser" -> result.success(isDefaultBrowser())
                    "openDefaultBrowserSettings" -> {
                        openDefaultBrowserSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }

    private fun tabEvent(tabId: String, type: String, data: Map<String, Any?>) {
        channel?.invokeMethod("tabEvent", HashMap(data).apply {
            put("tabId", tabId)
            put("type", type)
        })
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
            channel?.invokeMethod("systemUi", true)
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
        if (requestCode == REQUEST_FILE) {
            fileCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data))
            fileCallback = null
            channel?.invokeMethod("systemUi", false)
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
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            tabEvent(tab.id, "download", mapOf("name" to name, "started" to false))
            return
        }
        val request = DownloadManager.Request(Uri.parse(url))
            .setMimeType(mime)
            .addRequestHeader("User-Agent", userAgent)
            .setTitle(name)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, name)
        // Private tabs keep their cookies in their own profile, never shared.
        if (!tab.isPrivate) {
            CookieManager.getInstance().getCookie(url)?.let { request.addRequestHeader("Cookie", it) }
        }
        getSystemService(DownloadManager::class.java)?.enqueue(request)
        tabEvent(tab.id, "download", mapOf("name" to name, "started" to true))
    }

    override fun onCrashed(tab: ZtTab) {
        tabs.remove(tab.id)
        tab.destroy()
        tabEvent(tab.id, "crashed", emptyMap())
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

    /** Cookies, site storage and cache of normal tabs. */
    private fun clearBrowsingData() {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        WebStorage.getInstance().deleteAllData()
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
        super.onDestroy()
    }

    companion object {
        private const val REQUEST_FILE = 4101
        private const val REQUEST_ROLE = 4102
    }
}
