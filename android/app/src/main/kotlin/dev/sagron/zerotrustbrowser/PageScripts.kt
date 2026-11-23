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
 * - [holdBlob] keeps a blob: download and reads it back a piece at a time.
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
     * Listens for one message carrying [key] and a port, reads the blob at
     * [url] and keeps it (the page may revoke the address), says its size
     * ("size:N"), then sends it a [piece] at a time, each when the app asks
     * ("next"), as "c:" + base64, then "end" (or "error"). "stop" lets go.
     */
    fun holdBlob(url: String, key: String, piece: Int): String =
        "(function(k,u){window.addEventListener('message',function f(e){" +
            "if(e.data!==k||!e.ports||!e.ports[0])return;window.removeEventListener('message',f,true);" +
            "e.stopImmediatePropagation();var p=e.ports[0],b=null,o=0,w=false,S=$piece;" +
            "function send(){if(!b)return;if(o>=b.size){p.postMessage('end');b=null;return;}" +
            "var s=b.slice(o,o+S);o+=S;var fr=new FileReader();" +
            "fr.onload=function(){var r=String(fr.result);p.postMessage('c:'+r.substring(r.indexOf(',')+1));};" +
            "fr.onerror=function(){p.postMessage('error');};fr.readAsDataURL(s);}" +
            "p.onmessage=function(m){if(m.data==='next'){if(b)send();else w=true;}" +
            "else if(m.data==='stop'){b=null;try{p.close();}catch(x){}}};" +
            "fetch(u).then(function(r){return r.blob();}).then(function(x){b=x;p.postMessage('size:'+x.size);" +
            "if(w){w=false;send();}}).catch(function(){p.postMessage('error');});},true);})(" +
            JSONObject.quote(key) + "," + JSONObject.quote(url) + ");"

    /** The text selected on the page (top frame), as a JSON string. */
    const val SELECTION = "(function(){try{return String(window.getSelection()||'');}catch(e){return '';}})()"

    /**
     * Media playing in a frame (B26), reported to the app through the
     * `ztMedia` listener, which the script then hides from the page. The app
     * answers "play" or "pause" for the notification's buttons. With
     * [keepPlaying], a frame that played media is told the page stays
     * visible, so sites that pause in the background keep playing.
     */
    fun media(keepPlaying: Boolean): String = MEDIA_TEMPLATE.replace("%KEEP%", if (keepPlaying) "1" else "0")

    private const val MEDIA_TEMPLATE = """(function(){
var P=window.ztMedia;if(!P)return;
try{delete window.ztMedia;}catch(e){}
var KEEP=%KEEP%,last=null,vis=false;
function send(o){try{P.postMessage(JSON.stringify(o));}catch(e){}}
function keepVisible(){if(vis||!KEEP)return;vis=true;
try{Object.defineProperty(Document.prototype,'hidden',{get:function(){return false},configurable:true});
Object.defineProperty(Document.prototype,'visibilityState',{get:function(){return 'visible'},configurable:true});}catch(e){}
['visibilitychange','webkitvisibilitychange'].forEach(function(n){
window.addEventListener(n,function(e){e.stopImmediatePropagation();},true);});}
document.addEventListener('play',function(e){var m=e.target;
if(!(m instanceof HTMLMediaElement))return;last=m;keepVisible();
send({s:'play',t:document.title||'',v:m.tagName==='VIDEO'});},true);
function stopped(e){if(e.target===last)send({s:'pause'});}
document.addEventListener('pause',stopped,true);
document.addEventListener('ended',stopped,true);
P.onmessage=function(e){if(!last)return;
if(e.data==='pause')last.pause();else if(e.data==='play'){var r=last.play();if(r&&r.catch)r.catch(function(){});}};
})();"""

    // ---- Fill code (one-time codes from ZT Authenticator) ------------------

    /**
     * Finds the page's one-time code field: an input marked
     * autocomplete="one-time-code", one whose name, label or placeholder
     * says so, or a row of 4 to 8 one-character boxes. Returns the inputs
     * to fill (several for boxes), the focused one first.
     */
    private const val FIND_CODE = """function ztFindCode(){
var T={'':1,text:1,tel:1,number:1,password:1};
var RE=/one.?time|otp|totp|2fa|mfa|two.?factor|2.?step|verif|security.?code|auth\w*.?code|access.?code|login.?code|sms.?code|passcode|\bcode\b|\bpin\b|קוד|אימות/i;
var NOT=/zip|postal|post.?code|promo|coupon|voucher|gift|country|area|phone|captcha|discount|referr|invit/i;
function ok(e){if(e.disabled||e.readOnly)return false;
if(!T[(e.getAttribute('type')||'').toLowerCase()])return false;
var r=e.getBoundingClientRect();return r.width>0&&r.height>0;}
function words(e){var l='';try{if(e.labels&&e.labels.length)l=e.labels[0].textContent||'';}catch(x){}
return [e.name,e.id,e.getAttribute('aria-label'),e.getAttribute('placeholder'),e.getAttribute('data-testid'),l].join(' ');}
var all=[].slice.call(document.querySelectorAll('input')).filter(ok);
var a=document.activeElement;
function first(l){if(a&&l.indexOf(a)>0){l.splice(l.indexOf(a),1);l.unshift(a);}return l;}
var one=all.filter(function(e){return /one-time-code/i.test(e.getAttribute('autocomplete')||'');});
if(!one.length)one=all.filter(function(e){var w=words(e),m=e.maxLength;
return (m<0||m>=4)&&RE.test(w)&&!NOT.test(w)&&!/pass.?word/i.test(w);});
if(one.length)return {boxes:false,list:first(one)};
var box=all.filter(function(e){return e.maxLength===1;});
if(box.length>=4&&box.length<=8)return {boxes:true,list:box};
return null;}"""

    /**
     * B-Auth: the top frame tells the app ("ztCode" listener) when it has a
     * one-time code field, also when one appears later (single-page sign-in
     * forms). The listener is hidden from the page.
     */
    const val CODE_FIELDS = """(function(){
if(window.top!==window)return;
var P=window.ztCode;if(!P)return;
try{delete window.ztCode;}catch(e){}
""" + FIND_CODE + """
var last=null,timer=0;
function check(){timer=0;var now=ztFindCode()?'1':'0';if(now!==last){last=now;try{P.postMessage(now);}catch(e){}}}
function soon(){if(!timer)timer=setTimeout(check,700);}
document.addEventListener('DOMContentLoaded',check);
window.addEventListener('load',check);
document.addEventListener('focusin',function(e){if(e.target&&e.target.tagName==='INPUT')check();},true);
try{new MutationObserver(soon).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['style','class','hidden','disabled']});}catch(e){}
})();"""

    /** Whether the page has a one-time code field ("true"/"false"). */
    const val HAS_CODE_FIELD = "(function(){" + FIND_CODE + "return !!ztFindCode();})()"

    /**
     * Puts [code] in the page's code field the way typing does (the page's
     * own scripts see input and change events). Returns true when filled.
     */
    fun fillCode(code: String): String = "(function(C){" + FIND_CODE + """
var f=ztFindCode();if(!f)return false;
var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
function put(e,v){try{e.focus();}catch(x){}set.call(e,v);
e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}
if(f.boxes){if(f.list.length<C.length)return false;for(var i=0;i<C.length;i++)put(f.list[i],C.charAt(i));}
else put(f.list[0],C);
return true;})(""" + JSONObject.quote(code) + ");"

    private var translateSrc: String? = null

    /**
     * B16: the page side of translation (assets/translate/page.js), an
     * expression giving an object with collect(max), apply(results),
     * restore() and dirty. [key] names its state on the page.
     */
    fun translate(context: Context, key: String): String {
        val src = translateSrc ?: asset(context, "assets/translate/page.js").trim().also { translateSrc = it }
        return src.replace("__ZTKEY__", key)
    }

    /** The page's declared language and a sample of its text (B16). */
    const val PAGE_LANGUAGE =
        "JSON.stringify({lang:(document.documentElement.lang||'')," +
            "sample:(document.body?document.body.innerText:'').slice(0,3000)})"

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
