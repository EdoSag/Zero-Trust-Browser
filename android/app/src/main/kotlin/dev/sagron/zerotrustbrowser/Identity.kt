package dev.sagron.zerotrustbrowser

import android.content.Context
import android.os.Build
import android.webkit.WebSettings
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject
import java.security.SecureRandom

/**
 * B42: what the browser tells sites it is (the "user agent").
 *
 * Three things have to say the same, or a site sees a mismatch:
 * - the `User-Agent` header and `navigator.userAgent`: the engine's own
 *   user agent setting, so every request, frame and worker gets it;
 * - the Client Hints headers (`Sec-CH-UA`, `-Mobile`, `-Platform`, and the
 *   detailed ones a site may ask for) and `navigator.userAgentData`: the
 *   engine's user agent metadata, so they too are real engine values and
 *   not patched in by a script;
 * - the few `navigator` fields the engine doesn't derive from those
 *   (`platform`, `vendor`, `oscpu`...): a small document-start script,
 *   added only when an identity needs it.
 *
 * With nothing chosen, the browser is Chrome on Android, at this phone's
 * real engine version: one settings call when a tab is made, no script and
 * nothing to do per page ([bySite] is false, [resolve] returns at once).
 *
 * Dart builds the identities (lib/browser/identity.dart) and hands them
 * over as maps; `{chrome}` and `{android}` in their texts stand for this
 * phone's engine and Android versions, filled in here.
 */
object Identity {
    /**
     * Client Hints for an identity. [brand] null: a browser that has none
     * (Firefox, Safari); the engine still sends the three basic headers,
     * so they name the claimed system and no browser. [device]: keep this
     * phone's own system, model and version (the default identity).
     */
    data class Hints(
        val brand: String?,
        val brandVersion: String,
        val chromium: String,
        val platform: String,
        val platformVersion: String,
        val arch: String,
        val bitness: Int,
        val model: String,
        val mobile: Boolean,
        val formFactor: String,
        val device: Boolean = false,
    )

    /** One identity; null fields are left as the engine has them. */
    data class Spec(
        val id: String,
        val userAgent: String,
        val hints: Hints,
        val platform: String? = null,
        val vendor: String? = null,
        val oscpu: String? = null,
        val appVersion: String? = null,
        val productSub: String? = null,
        val touch: Int? = null,
    )

    /**
     * What a tab, a site rule or the settings ask for: one identity (with
     * the one to use for "Desktop site"), a [pool] to pick from at random,
     * or, with all three null, the default.
     */
    class Target(val spec: Spec?, val desktop: Spec?, val pool: List<Target>?)

    /** One entry of `Sec-CH-UA` and of `navigator.userAgentData.brands`. */
    data class Brand(val name: String, val major: String, val full: String)

    /** For every site without a rule, from Settings; null is the default. */
    @Volatile private var global: Target? = null

    /** Host (and its subdomains) to what it gets. */
    @Volatile private var rules: Map<String, Target> = emptyMap()

    /**
     * True when the identity can differ from one site to the next (site
     * rules, or a random one per site), so tabs look at each page's host.
     */
    @Volatile var bySite = false
        private set

    private val random = SecureRandom()

    /** The random pick per site, kept until the app restarts or [shuffle]. */
    private val picks = HashMap<String, Int>()

    private var engineMajor = 0
    private var engineFull = ""
    private var defaultSpec: Spec? = null
    private var desktopSpec: Spec? = null

    /** Reads this phone's engine version, once. */
    private fun ensure(context: Context) {
        if (defaultSpec != null) return
        val ua = try {
            WebSettings.getDefaultUserAgent(context)
        } catch (e: Exception) {
            ""
        }
        val found = Regex("Chrome/(\\d+)\\.(\\d+)\\.(\\d+)\\.(\\d+)").find(ua)
        engineMajor = found?.groupValues?.get(1)?.toIntOrNull() ?: 130
        val inUa = found?.value?.removePrefix("Chrome/")
        // A shortened user agent says "142.0.0.0"; the package has the rest.
        val fromPackage = try {
            WebViewCompat.getCurrentWebViewPackage(context)?.versionName
                ?.let { Regex("^\\d+\\.\\d+\\.\\d+\\.\\d+").find(it)?.value }
        } catch (e: Exception) {
            null
        }
        engineFull = when {
            inUa != null && !inUa.endsWith(".0.0.0") -> inUa
            fromPackage != null && fromPackage.startsWith("$engineMajor.") -> fromPackage
            else -> estimatedFull(engineMajor)
        }
        // Tablets have no "Mobile" in theirs, as in Chrome.
        val mobile = ua.isEmpty() || ua.contains(" Mobile ")
        val m = engineMajor.toString()
        defaultSpec = Spec(
            id = DEFAULT,
            userAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/$m.0.0.0 ${if (mobile) "Mobile " else ""}Safari/537.36",
            hints = Hints(
                "Google Chrome", m, m, "", "", "", 0, "", mobile,
                if (mobile) "Mobile" else "Tablet", device = true,
            ),
        )
        desktopSpec = Spec(
            id = DEFAULT_DESKTOP,
            userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/$m.0.0.0 Safari/537.36",
            hints = Hints("Google Chrome", m, m, "Linux", "6.8.0", "x86", 64, "", false, "Desktop"),
            platform = "Linux x86_64",
        )
    }

    /** For the settings screen: versions and the default's user agents. */
    fun info(context: Context): Map<String, Any?> {
        ensure(context)
        return mapOf(
            "chrome" to engineMajor.toString(),
            "chromeFull" to engineFull,
            "android" to androidVersion(),
            "defaultUa" to defaultSpec?.userAgent,
            "desktopUa" to desktopSpec?.userAgent,
            "clientHints" to WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA),
        )
    }

    /** The settings' identity and the site rules, from Dart. */
    fun set(context: Context, globalMap: Map<*, *>?, ruleMaps: Map<*, *>?) {
        if (globalMap != null || !ruleMaps.isNullOrEmpty()) ensure(context)
        val g = target(globalMap)
        val r = HashMap<String, Target>()
        for ((host, value) in ruleMaps ?: emptyMap<Any?, Any?>()) {
            val h = (host as? String)?.lowercase()?.trim('.') ?: continue
            r[h] = target(value as? Map<*, *>) ?: Target(null, null, null)
        }
        global = g?.takeUnless { it.spec == null && it.pool == null }
        rules = r
        bySite = r.isNotEmpty() || global?.pool != null
    }

    /** A target from Dart's map; null for no map. */
    fun target(context: Context, m: Map<*, *>?): Target? {
        if (m != null) ensure(context)
        return target(m)
    }

    private fun target(m: Map<*, *>?): Target? {
        if (m == null) return null
        val pool = (m["pool"] as? List<*>)?.mapNotNull { target(it as? Map<*, *>) }
        if (!pool.isNullOrEmpty()) return Target(null, null, pool)
        return Target(spec(m["spec"] as? Map<*, *>), spec(m["desktop"] as? Map<*, *>), null)
    }

    private fun spec(m: Map<*, *>?): Spec? {
        if (m == null) return null
        val ua = fill(m["ua"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val h = m["hints"] as? Map<*, *> ?: return null
        return Spec(
            id = m["id"] as? String ?: "custom",
            // A line break would end the header.
            userAgent = ua.replace(Regex("[\\r\\n]+"), " ").trim(),
            hints = Hints(
                brand = (h["brand"] as? String)?.takeIf { it.isNotBlank() },
                brandVersion = fill(h["brandVersion"] as? String) ?: "",
                chromium = fill(h["chromium"] as? String) ?: "",
                platform = (h["platform"] as? String)?.takeIf { it.isNotBlank() } ?: "Unknown",
                platformVersion = fill(h["platformVersion"] as? String) ?: "",
                arch = h["arch"] as? String ?: "",
                bitness = (h["bitness"] as? Number)?.toInt() ?: 0,
                model = h["model"] as? String ?: "",
                mobile = h["mobile"] as? Boolean ?: false,
                formFactor = h["formFactor"] as? String ?: "Desktop",
            ),
            platform = m["platform"] as? String,
            vendor = m["vendor"] as? String,
            oscpu = m["oscpu"] as? String,
            appVersion = fill(m["appVersion"] as? String),
            productSub = m["productSub"] as? String,
            touch = (m["touch"] as? Number)?.toInt(),
        )
    }

    private fun fill(text: String?): String? = text
        ?.replace("{chrome}", engineMajor.toString())
        ?.replace("{android}", androidVersion())

    private fun androidVersion(): String =
        Regex("^\\d+(\\.\\d+)*").find(Build.VERSION.RELEASE ?: "")?.value ?: "14"

    /**
     * The identity for a page on [host] in a tab: the tab's own choice
     * ([tab]), else the rule for the site, else the settings' one, else
     * the default. [desktop] is the tab's "Desktop site" switch.
     */
    fun resolve(context: Context, tab: Target?, desktop: Boolean, private: Boolean, host: String?): Spec {
        ensure(context)
        val picked = pick(tab ?: ruleFor(host) ?: global, private, host)
        return when {
            picked?.spec == null -> if (desktop) desktopSpec!! else defaultSpec!!
            desktop -> picked.desktop ?: picked.spec
            else -> picked.spec
        }
    }

    private fun ruleFor(host: String?): Target? {
        val r = rules
        if (r.isEmpty() || host == null) return null
        var h = host.lowercase().trim('.')
        while (true) {
            r[h]?.let { return it }
            val dot = h.indexOf('.')
            if (dot < 0) return null
            h = h.substring(dot + 1)
        }
    }

    /**
     * One of a pool, the same for a site until the app restarts or
     * [shuffle]: a site that saw a new browser on every page would sign
     * the user out. Private tabs get picks of their own.
     */
    private fun pick(t: Target?, private: Boolean, host: String?): Target? {
        val pool = t?.pool ?: return t
        val key = (if (private) "p:" else "n:") + Blocker.siteOf((host ?: "").lowercase())
        val i = synchronized(picks) {
            if (picks.size > 2000) picks.clear()
            picks.getOrPut(key) { random.nextInt(1 shl 20) }
        }
        return pool[i % pool.size]
    }

    /** New random picks from now on. */
    fun shuffle() = synchronized(picks) { picks.clear() }

    /** The last private tab closed: its picks go with it. */
    fun forgetPrivate() = synchronized(picks) { picks.keys.removeAll { it.startsWith("p:") } }

    // ---- Client Hints -------------------------------------------------------

    /** The engine's user agent metadata for [spec] (needs USER_AGENT_METADATA). */
    fun metadata(spec: Spec): UserAgentMetadata {
        val h = spec.hints
        val chromium = h.chromium.toIntOrNull() ?: engineMajor
        val chromiumFull = fullVersion(chromium)
        val brandFull = if (h.brandVersion == chromium.toString()) chromiumFull else "${h.brandVersion}.0.0.0"
        val list = brands(h.brand, h.brandVersion, brandFull, chromium, chromiumFull)
        val b = UserAgentMetadata.Builder()
            .setBrandVersionList(
                list.map {
                    UserAgentMetadata.BrandVersion.Builder()
                        .setBrand(it.name).setMajorVersion(it.major).setFullVersion(it.full).build()
                },
            )
            .setFullVersion(if (h.brand == null) list.first().full else brandFull)
            .setMobile(h.mobile)
            .setWow64(false)
        // Left alone, these stay this phone's own (the default identity).
        if (!h.device) {
            b.setPlatform(h.platform)
                .setPlatformVersion(h.platformVersion)
                .setArchitecture(h.arch)
                .setModel(h.model)
                .setBitness(h.bitness)
            if (WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA_FORM_FACTORS)) {
                b.setFormFactors(listOf(h.formFactor))
            }
        }
        return b.build()
    }

    /** The full version to go with [major]: this engine's own when it is the same. */
    private fun fullVersion(major: Int): String = if (major == engineMajor) engineFull else estimatedFull(major)

    /**
     * A likely full version for Chromium [major] (its build number rises
     * by about 61 a version: 120 was 6099, 131 was 6778, 142 was 7444).
     */
    fun estimatedFull(major: Int): String = "$major.0.${6099 + (major - 120) * 61}.${60 + major % 40}"

    /**
     * The brand list as Chromium builds it (GenerateBrandVersionList in
     * components/embedder_support/user_agent_utils.cc): a made-up "not a
     * brand" entry, "Chromium" and the browser, in an order and with
     * punctuation that depend on the Chromium version. Chrome 131 sends
     * `"Google Chrome";v="131", "Chromium";v="131", "Not_A Brand";v="24"`.
     * With no [brand], only the made-up entry.
     */
    fun brands(brand: String?, brandMajor: String, brandFull: String, chromium: Int, chromiumFull: String): List<Brand> {
        val seed = if (chromium < 0) 0 else chromium
        val chars = listOf(" ", "(", ":", "-", ".", "/", ")", ";", "=", "?", "_")
        val versions = listOf("8", "99", "24")
        val greaseVersion = versions[seed % versions.size]
        val grease = Brand(
            "Not" + chars[seed % chars.size] + "A" + chars[(seed + 1) % chars.size] + "Brand",
            greaseVersion,
            "$greaseVersion.0.0.0",
        )
        if (brand == null) return listOf(grease)
        val orders = listOf(
            listOf(0, 1, 2), listOf(0, 2, 1), listOf(1, 0, 2),
            listOf(1, 2, 0), listOf(2, 0, 1), listOf(2, 1, 0),
        )
        val order = orders[seed % orders.size]
        val out = arrayOfNulls<Brand>(3)
        out[order[0]] = grease
        out[order[1]] = Brand("Chromium", chromium.toString(), chromiumFull)
        out[order[2]] = Brand(brand, brandMajor.ifBlank { chromium.toString() }, brandFull)
        return out.filterNotNull()
    }

    // ---- Page script --------------------------------------------------------

    /**
     * The document-start script for [spec], or null when the engine
     * already says everything itself (the default, any Chrome on Android).
     */
    fun script(spec: Spec): String? {
        val noHints = spec.hints.brand == null
        if (!noHints && spec.platform == null && spec.vendor == null && spec.oscpu == null &&
            spec.appVersion == null && spec.productSub == null && spec.touch == null
        ) {
            return null
        }
        val o = JSONObject()
        spec.platform?.let { o.put("platform", it) }
        spec.vendor?.let { o.put("vendor", it) }
        spec.oscpu?.let { o.put("oscpu", it) }
        spec.appVersion?.let { o.put("appVersion", it) }
        spec.productSub?.let { o.put("productSub", it) }
        spec.touch?.let { o.put("maxTouchPoints", it) }
        return SCRIPT.replace("%FIELDS%", o.toString()).replace("%NO_HINTS%", if (noHints) "1" else "0")
    }

    const val DEFAULT = "default"
    const val DEFAULT_DESKTOP = "default-desktop"

    /**
     * Runs in every frame before the page's own scripts. The fields are
     * set on `Navigator.prototype`, where the engine has them, so
     * `navigator.platform` and `Navigator.prototype.platform` agree.
     * Browsers without Client Hints have no `navigator.userAgentData`.
     */
    private const val SCRIPT = """(function(){
var F=%FIELDS%,N=Navigator.prototype;
Object.keys(F).forEach(function(k){var v=F[k];
try{Object.defineProperty(N,k,{get:function(){return v},enumerable:true,configurable:true});}catch(e){}});
if(%NO_HINTS%){try{delete N.userAgentData;}catch(e){}try{delete window.NavigatorUAData;}catch(e){}}
})();"""
}
