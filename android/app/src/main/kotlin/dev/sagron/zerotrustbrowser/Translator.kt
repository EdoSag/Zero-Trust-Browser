package dev.sagron.zerotrustbrowser

import android.annotation.SuppressLint
import android.app.Activity
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream

/**
 * B16: translates text on the phone with Firefox's translation engine
 * (Bergamot, MPL-2.0, in assets/translate) and the language models the
 * app downloaded into [modelsDir].
 *
 * The engine runs in its own hidden WebView, never in the page's: its
 * only origin is https://translate.zt, which exists only inside this app
 * (every request is answered here, from the app's assets and model files,
 * and anything else is refused), so the engine can't reach the network
 * and the page can't reach the engine. It stops after a few idle minutes
 * to give its memory back.
 */
class Translator(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var web: WebView? = null
    private var ready = false
    private val queued = ArrayList<String>()
    private val pending = HashMap<Int, (List<String>?, String?) -> Unit>()
    private var nextId = 1
    private val idleStop = Runnable { stop() }

    /** Where the downloaded models and their registry.json are. */
    @Volatile var modelsDir: File? = null

    /**
     * Translates [texts] (HTML fragments when [html]) from [from] to [to];
     * [done] gets the translations in the same order, or an error.
     */
    fun translate(
        from: String,
        to: String,
        texts: List<String>,
        html: Boolean,
        done: (List<String>?, String?) -> Unit,
    ) {
        val id = nextId++
        pending[id] = done
        val job = JSONObject()
            .put("id", id)
            .put("from", from)
            .put("to", to)
            .put("html", html)
            .put("texts", JSONArray(texts))
        run("zt.run(${job})")
    }

    /** The models changed (downloaded or deleted): load them afresh. */
    fun reset() {
        if (web != null) run("zt.reset()")
    }

    fun stop() {
        main.removeCallbacks(idleStop)
        val w = web ?: return
        web = null
        ready = false
        queued.clear()
        (w.parent as? ViewGroup)?.removeView(w)
        w.destroy()
        val failed = pending.values.toList()
        pending.clear()
        failed.forEach { it(null, "stopped") }
    }

    private fun run(script: String) {
        main.removeCallbacks(idleStop)
        val w = web ?: start()
        if (ready) w.evaluateJavascript(script, null) else queued.add(script)
    }

    private fun onMessage(raw: String) {
        val msg = try {
            JSONObject(raw)
        } catch (e: Exception) {
            return
        }
        if (msg.optBoolean("ready")) {
            ready = true
            val w = web ?: return
            queued.forEach { w.evaluateJavascript(it, null) }
            queued.clear()
            return
        }
        val done = pending.remove(msg.optInt("id")) ?: return
        val out = msg.optJSONArray("out")
        if (out != null) {
            done(List(out.length()) { out.optString(it) }, null)
        } else {
            done(null, msg.optString("error", "failed"))
        }
        if (pending.isEmpty()) main.postDelayed(idleStop, IDLE_MS)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun start(): WebView {
        val w = WebView(activity)
        web = w
        ready = false
        val s = w.settings
        s.javaScriptEnabled = true
        s.allowFileAccess = false
        s.allowContentAccess = false
        s.domStorageEnabled = false
        w.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse = serve(request.url)
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(w, "ztTranslate", setOf(ORIGIN)) { _, message, _, _, _ ->
                message.data?.let { onMessage(it) }
            }
        }
        // Attached (invisible, 1 pixel) so its timers and workers run at
        // full speed.
        val root = activity.window.decorView as ViewGroup
        w.visibility = View.INVISIBLE
        root.addView(w, FrameLayout.LayoutParams(1, 1))
        w.loadUrl("$ORIGIN/index.html")
        return w
    }

    /** Answers every request of the engine's WebView; nothing goes out. */
    private fun serve(url: Uri): WebResourceResponse {
        if (url.scheme != "https" || url.host != HOST) return refuse()
        val path = url.path?.trimStart('/') ?: return refuse()
        if (path.contains("..")) return refuse()
        return try {
            if (path.startsWith("models/")) {
                val dir = modelsDir ?: return refuse()
                val file = File(dir, path.removePrefix("models/")).canonicalFile
                if (!file.path.startsWith(dir.canonicalPath + File.separator) || !file.isFile) {
                    return refuse(404)
                }
                ok(mime(path), FileInputStream(file))
            } else {
                val key = FlutterInjector.instance().flutterLoader()
                    .getLookupKeyForAsset("assets/translate/$path")
                ok(mime(path), activity.assets.open(key))
            }
        } catch (e: Exception) {
            refuse(404)
        }
    }

    private fun ok(mime: String, data: java.io.InputStream) =
        WebResourceResponse(
            mime,
            if (mime.startsWith("text/") || mime.endsWith("javascript") || mime.endsWith("json")) "utf-8" else null,
            200,
            "OK",
            mapOf("Cache-Control" to "no-store"),
            data,
        )

    private fun refuse(code: Int = 403) =
        WebResourceResponse("text/plain", "utf-8", code, "Refused", emptyMap(), ByteArrayInputStream(ByteArray(0)))

    private fun mime(path: String) = when (path.substringAfterLast('.', "")) {
        "html" -> "text/html"
        "js" -> "application/javascript"
        "wasm" -> "application/wasm"
        "json" -> "application/json"
        else -> "application/octet-stream"
    }

    companion object {
        const val HOST = "translate.zt"
        const val ORIGIN = "https://$HOST"
        private const val IDLE_MS = 3 * 60 * 1000L
    }
}
