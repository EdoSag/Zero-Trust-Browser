package dev.sagron.zerotrustbrowser

import android.content.Context
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom

/**
 * The JavaScript ZT Browser puts into pages.
 *
 * - [documentStart] runs in every frame before the page's own scripts:
 *   Global Privacy Control, fingerprinting protection, and the generic CSS
 *   that hides ad boxes and cookie banners (top frame only). It is rebuilt
 *   when settings or the blocklist change ([invalidate]).
 * - [siteCss] adds a site's own hiding rules once the page shows.
 * - [extractArticle] and [readerable] use Mozilla Readability for reader mode.
 * - [fetchBlob] reads a blob: download back to the app.
 */
object PageScripts {
    /** Fingerprinting protection, pushed from Dart (`setPrivacy`). */
    @Volatile var fingerprinting = true

    /**
     * Random per app start: noise added to canvas and audio readouts is the
     * same on one site for a session (so pages work), but different across
     * sites and sessions (so it can't be used to follow you).
     */
    private val seed: Long = SecureRandom().nextInt().toLong() and 0xffffffffL

    @Volatile private var cached: String? = null
    private var readability: String? = null
    private var readerableSrc: String? = null

    fun invalidate() {
        cached = null
    }

    fun documentStart(): String {
        cached?.let { return it }
        val off = JSONArray(Blocker.allowedSites.toList())
        val hideOff = JSONObject().apply { for (d in Blocker.genericOff) put(d, 1) }
        val css = if (Blocker.enabled && Blocker.hideElements) Blocker.genericCss else ""
        val script = START_TEMPLATE
            .replace("%OFF%", off.toString())
            .replace("%HIDE_OFF%", hideOff.toString())
            .replace("%FP%", if (fingerprinting) "1" else "0")
            .replace("%SEED%", seed.toString())
            .replace("%CSS%", JSONObject.quote(css))
        cached = script
        return script
    }

    /** Adds [css] to the page as a style sheet the page's DOM doesn't show. */
    fun siteCss(css: String): String = "(function(c){try{var s=new CSSStyleSheet();s.replaceSync(c);" +
        "document.adoptedStyleSheets=document.adoptedStyleSheets.concat([s]);}catch(e){}})(" +
        JSONObject.quote(css) + ");"

    /** Returns the article as a JSON string, or null when there is none. */
    fun extractArticle(context: Context): String {
        val src = readability ?: (asset(context, "assets/reader/Readability.js") + "\n").also { readability = it }
        return "(function(){var module;\n$src\ntry{var a=new Readability(document.cloneNode(true)," +
            "{charThreshold:300}).parse();if(!a||!a.content)return null;return JSON.stringify({" +
            "title:a.title,byline:a.byline,siteName:a.siteName,content:a.content,excerpt:a.excerpt," +
            "lang:a.lang,dir:a.dir,length:a.length});}catch(e){return null;}})()"
    }

    /** True when the page looks like an article that reader mode can show. */
    fun readerable(context: Context): String {
        val src = readerableSrc ?: (asset(context, "assets/reader/Readability-readerable.js") + "\n")
            .also { readerableSrc = it }
        return "(function(){var module;\n$src\ntry{return isProbablyReaderable(document);}catch(e){return false;}})()"
    }

    /**
     * Listens for one message carrying [key] and a port, then sends the
     * blob at [url] back over the port as a data: URL (or "error").
     */
    fun fetchBlob(url: String, key: String, maxBytes: Long): String =
        "(function(k,u){window.addEventListener('message',function f(e){" +
            "if(e.data!==k||!e.ports||!e.ports[0])return;window.removeEventListener('message',f,true);" +
            "e.stopImmediatePropagation();var p=e.ports[0];" +
            "fetch(u).then(function(r){return r.blob();}).then(function(b){" +
            "if(b.size>$maxBytes){p.postMessage('error:size');return;}" +
            "var fr=new FileReader();fr.onload=function(){p.postMessage(fr.result);};" +
            "fr.onerror=function(){p.postMessage('error');};fr.readAsDataURL(b);" +
            "}).catch(function(){p.postMessage('error');});},true);})(" +
            JSONObject.quote(key) + "," + JSONObject.quote(url) + ");"

    private fun asset(context: Context, name: String): String {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(name)
        return context.assets.open(key).bufferedReader().use { it.readText() }
    }

    private const val START_TEMPLATE = """(function(){
var OFF=%OFF%,HIDE_OFF=%HIDE_OFF%,FP=%FP%,SEED=%SEED%,CSS=%CSS%;
try{Object.defineProperty(Navigator.prototype,'globalPrivacyControl',{get:function(){return true},configurable:true});}catch(e){}
function siteOf(h){h=h.replace(/\.${'$'}/,'');var l=h.split('.');if(l.length<=2)return h;
var t=l[l.length-1],s=l[l.length-2];return l.slice(-((t.length==2&&s.length<=3)?3:2)).join('.');}
var host=(location.hostname||'').toLowerCase();
if(!host){try{host=(window.top.location.hostname||'').toLowerCase();}catch(e){}}
if(OFF.indexOf(siteOf(host))>=0)return;
if(FP)protect(siteOf(host));
if(CSS&&window.top===window){var d=host,skip=false;
while(d){if(HIDE_OFF[d]){skip=true;break;}var i=d.indexOf('.');if(i<0)break;d=d.substring(i+1);}
if(!skip){try{var st=new CSSStyleSheet();st.replaceSync(CSS);
document.adoptedStyleSheets=document.adoptedStyleSheets.concat([st]);}catch(e){}}}
function protect(site){
var h=SEED>>>0;for(var i=0;i<site.length;i++){h=Math.imul(h^site.charCodeAt(i),16777619)>>>0;}
function rnd(){h^=h<<13;h>>>=0;h^=h>>>17;h^=h<<5;h>>>=0;return h;}
var noise=[];for(var j=0;j<16;j++)noise.push(rnd());
function fixed(o,p,v){try{if(p in o)Object.defineProperty(o,p,{get:function(){return v},configurable:true});}catch(e){}}
fixed(Navigator.prototype,'hardwareConcurrency',8);
fixed(Navigator.prototype,'deviceMemory',8);
try{delete Navigator.prototype.getBattery;}catch(e){}
function farble(d){for(var k=0;k<d.length;k+=4){var n=noise[(k>>2)&15];if((n>>>((k>>2)%29))&1)d[k]^=1;}}
try{var C2=CanvasRenderingContext2D.prototype,gid=C2.getImageData;
C2.getImageData=function(){var r=gid.apply(this,arguments);if(r.width*r.height<=500000)farble(r.data);return r;};
var HC=HTMLCanvasElement.prototype,tdu=HC.toDataURL,tb=HC.toBlob;
function noisy(c){if(!c.width||!c.height||c.width*c.height>500000)return c;
try{var cp=document.createElement('canvas');cp.width=c.width;cp.height=c.height;var x=cp.getContext('2d');
x.drawImage(c,0,0);var dt=gid.call(x,0,0,c.width,c.height);farble(dt.data);x.putImageData(dt,0,0);return cp;}catch(e){return c;}}
HC.toDataURL=function(){return tdu.apply(noisy(this),arguments);};
HC.toBlob=function(){return tb.apply(noisy(this),arguments);};}catch(e){}
[window.WebGLRenderingContext,window.WebGL2RenderingContext].forEach(function(G){if(!G)return;
var gp=G.prototype.getParameter;G.prototype.getParameter=function(p){
if(p===37445)return 'Google Inc.';if(p===37446)return 'ANGLE (Generic GPU)';return gp.apply(this,arguments);};});
try{if(window.AudioBuffer){var gcd=AudioBuffer.prototype.getChannelData,seen=new WeakSet();
AudioBuffer.prototype.getChannelData=function(){var a=gcd.apply(this,arguments);
if(!seen.has(a)){seen.add(a);for(var q=0;q<a.length;q+=97)a[q]+=(noise[q&15]&1)?1e-7:-1e-7;}return a;};}}catch(e){}
}
})();"""
}
