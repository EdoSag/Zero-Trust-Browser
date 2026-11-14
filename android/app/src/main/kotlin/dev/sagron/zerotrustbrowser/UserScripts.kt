package dev.sagron.zerotrustbrowser

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.webkit.CookieManager
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * B41: user scripts (Tampermonkey / Greasemonkey format).
 *
 * Dart hands over the enabled scripts ([set]); each tab adds them as
 * document-start scripts ([injections]): first the runtime
 * (assets/userscripts/runtime.js) that takes the `ztUserScripts` bridge and
 * gives each script its GM_* functions, then one injection per script (so
 * a broken script can't stop the others), then a last one that removes the
 * runtime's name before any page script runs.
 *
 * What scripts store (GM_setValue) is kept on this phone only, encrypted
 * with a key in the Android Keystore, and never from private tabs.
 * Requests (GM_xmlhttpRequest) go out from here, only for scripts that
 * asked for them (@grant) and only to the sites they named (@connect),
 * and never to hosts the tracker blocklist blocks.
 */
object UserScripts {
    /** The names each script's function takes, in this order. */
    private val ARGS = listOf(
        "unsafeWindow", "GM", "GM_info", "GM_log", "GM_addStyle", "GM_addElement",
        "GM_getValue", "GM_setValue", "GM_deleteValue", "GM_listValues",
        "GM_getValues", "GM_setValues", "GM_deleteValues",
        "GM_addValueChangeListener", "GM_removeValueChangeListener",
        "GM_getResourceText", "GM_getResourceURL", "GM_xmlhttpRequest",
        "GM_openInTab", "GM_setClipboard", "GM_notification",
        "GM_registerMenuCommand", "GM_unregisterMenuCommand",
    )

    /** Largest response a script gets back from a request. */
    private const val MAX_RESPONSE = 15L * 1024 * 1024

    class Script(
        val id: String,
        val name: String,
        val code: String,
        val config: JSONObject,
        val grants: Set<String>,
        val connects: List<String>,
        val allowPrivate: Boolean,
    ) {
        val canRequest: Boolean
            get() = grants.any { it.equals("GM_xmlhttpRequest", true) || it.equals("GM.xmlHttpRequest", true) }
    }

    @Volatile private var scripts: Map<String, Script> = emptyMap()
    private val values = HashMap<String, JSONObject>()
    private var valuesLoaded = false
    private var appVersion = ""
    private var runtimeSrc: String? = null
    private var cached = HashMap<Boolean, List<String>>()

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val net = Executors.newFixedThreadPool(4)
    private val inFlight = ConcurrentHashMap<String, Future<*>>()

    /** Called (main thread) when tabs should add the scripts again. */
    var onChanged: (() -> Unit)? = null
    private var refreshQueued = false
    private var saveQueued = false

    fun script(id: String?): Script? = id?.let { scripts[it] }

    fun isEmpty() = scripts.isEmpty()

    /** The enabled scripts, from Dart. */
    fun set(context: Context, list: List<Map<String, Any?>>) {
        loadValues(context)
        if (appVersion.isEmpty()) {
            appVersion = try {
                context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: ""
            } catch (e: Exception) {
                ""
            }
        }
        val next = LinkedHashMap<String, Script>()
        for (m in list) {
            val id = m["id"] as? String ?: continue
            val config = try {
                JSONObject(m["config"] as? String ?: "{}")
            } catch (e: Exception) {
                continue
            }
            next[id] = Script(
                id = id,
                name = m["name"] as? String ?: "",
                code = m["code"] as? String ?: "",
                config = config,
                grants = (m["grants"] as? List<*>)?.filterIsInstance<String>()?.toSet() ?: emptySet(),
                connects = (m["connects"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                allowPrivate = m["allowPrivate"] as? Boolean ?: false,
            )
        }
        scripts = next
        cached.clear()
        onChanged?.invoke()
    }

    /** The document-start scripts for a tab; empty when there are none. */
    fun injections(context: Context, isPrivate: Boolean): List<String> {
        cached[isPrivate]?.let { return it }
        val list = scripts.values.filter { !isPrivate || it.allowPrivate }
        if (list.isEmpty()) {
            cached[isPrivate] = emptyList()
            return emptyList()
        }
        val runtime = runtimeSrc ?: asset(context, "assets/userscripts/runtime.js").also { runtimeSrc = it }
        val bytes = ByteArray(9).also { SecureRandom().nextBytes(it) }
        val key = "__ztus" + Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.URL_SAFE)
            .replace("-", "a").replace("_", "b")
        val keyJs = JSONObject.quote(key)
        val out = ArrayList<String>()
        out.add(
            runtime.replace("%KEY%", keyJs)
                .replace("%ARGS%", JSONArray(ARGS).toString())
                .replace("%APP%", JSONObject.quote(appVersion))
                .replace("%PRIVATE%", if (isPrivate) "1" else "0"),
        )
        for (s in list) {
            val config = JSONObject(s.config.toString())
            config.put("id", s.id)
            config.put("values", synchronized(values) { JSONObject((values[s.id] ?: JSONObject()).toString()) })
            val file = s.name.replace(Regex("[^\\w\\- ]"), "").trim().ifEmpty { "script" }
            out.add(
                "(function(){var R=window[$keyJs];if(!R)return;R.run(${config},function(${ARGS.joinToString(",")}){\n" +
                    s.code + "\n});})();\n//# sourceURL=userscript:/$file.user.js",
            )
        }
        out.add("try{delete window[$keyJs];}catch(e){}")
        cached[isPrivate] = out
        return out
    }

    // ---- What scripts store ---------------------------------------------

    fun setValue(context: Context, id: String, key: String, raw: String?) {
        loadValues(context)
        synchronized(values) {
            val v = values.getOrPut(id) { JSONObject() }
            if (raw == null) v.remove(key) else v.put(key, raw)
            if (v.length() == 0) values.remove(id)
        }
        changedValues(context)
    }

    /** Removes what a deleted script stored. */
    fun forget(context: Context, id: String) {
        loadValues(context)
        synchronized(values) { values.remove(id) }
        changedValues(context)
    }

    /** Signed out: no scripts, nothing they stored. */
    fun clear(context: Context) {
        scripts = emptyMap()
        cached.clear()
        synchronized(values) { values.clear() }
        valuesLoaded = true
        io.execute { valuesFile(context).delete() }
        onChanged?.invoke()
    }

    private fun changedValues(context: Context) {
        cached.clear()
        if (!saveQueued) {
            saveQueued = true
            main.postDelayed({
                saveQueued = false
                val snapshot = synchronized(values) {
                    val all = JSONObject()
                    for ((id, v) in values) all.put(id, v)
                    all.toString()
                }
                io.execute { saveValues(context, snapshot) }
            }, 1000)
        }
        // New pages see the new values; batched, as a script may store a lot.
        if (!refreshQueued) {
            refreshQueued = true
            main.postDelayed({
                refreshQueued = false
                onChanged?.invoke()
            }, 1500)
        }
    }

    private fun valuesFile(context: Context) = File(context.noBackupFilesDir, "userscripts/values.bin")

    private fun loadValues(context: Context) {
        if (valuesLoaded) return
        valuesLoaded = true
        try {
            val f = valuesFile(context)
            if (!f.exists()) return
            val raw = f.readBytes()
            if (raw.size < 13) return
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, 12))
            val json = JSONObject(String(cipher.doFinal(raw, 12, raw.size - 12), Charsets.UTF_8))
            synchronized(values) {
                for (k in json.keys()) json.optJSONObject(k)?.let { values[k] = it }
            }
        } catch (e: Exception) {
            // Unreadable (a new key after a restore): start empty.
        }
    }

    private fun saveValues(context: Context, json: String) {
        try {
            val f = valuesFile(context)
            f.parentFile?.mkdirs()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(json.toByteArray(Charsets.UTF_8))
            val tmp = File(f.parentFile, "values.tmp")
            tmp.writeBytes(sealed)
            tmp.renameTo(f)
        } catch (e: Exception) {
            // Kept in memory until the next change.
        }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private const val KEY_ALIAS = "zt_userscript_values"

    // ---- Requests (GM_xmlhttpRequest) ----------------------------------

    /**
     * Whether [script] may send a request to [host] from a page on
     * [pageHost]: its own site always, otherwise the sites in @connect
     * (any site when it named none, as the install screen said).
     */
    fun mayConnect(script: Script, host: String, pageHost: String?): Boolean {
        val h = host.lowercase()
        val page = pageHost?.lowercase()
        if (page != null && (h == page || h.endsWith(".$page") || page.endsWith(".$h"))) return true
        if (script.connects.isEmpty()) return true
        for (raw in script.connects) {
            val c = raw.trim().lowercase()
            when {
                c == "*" -> return true
                c == "self" -> if (page != null && h == page) return true
                c == "localhost" -> if (h == "localhost" || h == "127.0.0.1" || h == "[::1]") return true
                c.isNotEmpty() && (h == c || h.endsWith(".$c")) -> return true
            }
        }
        return false
    }

    /**
     * Sends a script's request; [reply] gets the answer as JSON (on the
     * main thread): status, statusText, headers, finalUrl, type, b64, or
     * error ("blocked", "timeout", "failed", "too large").
     */
    fun request(
        msg: JSONObject,
        script: Script,
        pageHost: String?,
        isPrivate: Boolean,
        userAgent: String,
        reply: (String) -> Unit,
    ) {
        // Unique per frame (the runtime adds a random prefix), so two tabs
        // running the same script never share an entry.
        val n = msg.optString("n")
        val tag = "${script.id}:$n"
        fun answer(o: JSONObject) {
            inFlight.remove(tag)
            o.put("t", "xhr").put("n", n)
            val s = o.toString()
            main.post { reply(s) }
        }

        /** Null when [u] may be requested, else why not. */
        fun refused(u: URL): String? {
            if (u.protocol != "https" && u.protocol != "http") return "failed"
            val h = u.host ?: return "failed"
            if (!script.canRequest || !mayConnect(script, h, pageHost)) return "not allowed"
            if (Blocker.shouldBlock(h.lowercase(), pageHost)) return "blocked"
            return null
        }
        val first = try {
            URL(msg.optString("url"))
        } catch (e: Exception) {
            answer(JSONObject().put("error", "failed"))
            return
        }
        refused(first)?.let {
            answer(JSONObject().put("error", it))
            return
        }
        inFlight[tag] = net.submit(Runnable {
            var conn: HttpURLConnection? = null
            try {
                var url = first
                var method = msg.optString("method", "GET")
                var body: ByteArray? = when {
                    msg.has("b64") -> Base64.decode(msg.optString("b64"), Base64.DEFAULT)
                    msg.has("body") -> msg.optString("body").toByteArray(Charsets.UTF_8)
                    else -> null
                }
                val timeout = msg.optInt("timeout", 0).takeIf { it > 0 } ?: 60_000
                val headers = msg.optJSONObject("headers")
                val anonymous = msg.optBoolean("anonymous") || isPrivate
                var hops = 0
                var c: HttpURLConnection
                while (true) {
                    c = url.openConnection() as HttpURLConnection
                    conn = c
                    // HttpURLConnection has no PATCH (or other verbs): those fail.
                    c.requestMethod = method
                    c.connectTimeout = timeout
                    c.readTimeout = timeout
                    // Each redirect is checked like the first address.
                    c.instanceFollowRedirects = false
                    c.useCaches = false
                    c.setRequestProperty("User-Agent", userAgent)
                    var hasCookie = false
                    headers?.keys()?.forEach { k ->
                        if (k.equals("host", true)) return@forEach
                        if (k.equals("cookie", true)) hasCookie = true
                        c.setRequestProperty(k, headers.optString(k))
                    }
                    if (!anonymous && !hasCookie) {
                        CookieManager.getInstance().getCookie(url.toString())?.let { c.setRequestProperty("Cookie", it) }
                    }
                    val payload = body
                    if (payload != null && method != "GET" && method != "HEAD") {
                        c.doOutput = true
                        c.setFixedLengthStreamingMode(payload.size)
                        c.outputStream.use { it.write(payload) }
                    }
                    val code = c.responseCode
                    if (!anonymous) {
                        val here = url.toString()
                        for ((k, vs) in c.headerFields) {
                            if (k != null && k.equals("set-cookie", true)) {
                                for (v in vs) CookieManager.getInstance().setCookie(here, v)
                            }
                        }
                    }
                    val location = c.getHeaderField("Location")
                    if (code !in listOf(301, 302, 303, 307, 308) || location == null) break
                    if (++hops > 10) {
                        answer(JSONObject().put("error", "failed"))
                        return@Runnable
                    }
                    val next = URL(url, location)
                    refused(next)?.let {
                        answer(JSONObject().put("error", it))
                        return@Runnable
                    }
                    c.disconnect()
                    if (code == 303 || ((code == 301 || code == 302) && method == "POST")) {
                        method = "GET"
                        body = null
                    }
                    url = next
                }
                val status = c.responseCode
                val stream = if (status >= 400) c.errorStream else c.inputStream
                val out = ByteArrayOutputStream()
                stream?.use { input ->
                    val buf = ByteArray(16 * 1024)
                    var total = 0L
                    while (true) {
                        if (Thread.currentThread().isInterrupted) return@Runnable
                        val r = input.read(buf)
                        if (r < 0) break
                        total += r
                        if (total > MAX_RESPONSE) {
                            answer(JSONObject().put("error", "too large"))
                            return@Runnable
                        }
                        out.write(buf, 0, r)
                    }
                }
                val lines = StringBuilder()
                for ((k, vs) in c.headerFields) {
                    if (k == null) continue
                    for (v in vs) lines.append(k.lowercase()).append(": ").append(v).append("\r\n")
                }
                answer(
                    JSONObject()
                        .put("status", status)
                        .put("statusText", c.responseMessage ?: "")
                        .put("headers", lines.toString())
                        .put("finalUrl", url.toString())
                        .put("type", c.contentType ?: "")
                        .put("b64", Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)),
                )
            } catch (e: SocketTimeoutException) {
                answer(JSONObject().put("error", "timeout"))
            } catch (e: Exception) {
                if (!Thread.currentThread().isInterrupted) answer(JSONObject().put("error", "failed"))
            } finally {
                conn?.disconnect()
            }
        })
    }

    fun abort(scriptId: String, n: String) {
        inFlight.remove("$scriptId:$n")?.cancel(true)
    }

    private fun asset(context: Context, name: String): String {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(name)
        return context.assets.open(key).bufferedReader().use { it.readText() }
    }
}
