/* ZT Browser user scripts (B41): the page side.
 *
 * Runs first among the user script injections in every frame, before the
 * page's own scripts. It takes the `ztUserScripts` bridge to the app (and
 * hides it from the page), then leaves a runner under a random name that
 * only the user script injections after it know; the last injection
 * removes it, still before any page script runs.
 *
 * UserScripts.kt fills in KEY (the runner's name), ARGS (the names each
 * script's function takes, in order), APP (app version) and PRIVATE (1 in
 * private tabs: what scripts store isn't kept).
 */
(function () {
  var KEY = %KEY%, ARGS = %ARGS%, APP = %APP%, PRIVATE = %PRIVATE%;
  var W = window, P = W.ztUserScripts;
  try { delete W.ztUserScripts; } catch (e) {}
  // Taken now, before a page can replace them.
  var stringify = JSON.stringify, parse = JSON.parse, RE = RegExp,
    hasOwn = Object.prototype.hasOwnProperty, keysOf = Object.keys,
    defineProp = Object.defineProperty, setT = W.setTimeout,
    PromiseC = W.Promise, consoleRef = W.console, docRef = W.document,
    atobF = W.atob, btoaF = W.btoa, TD = W.TextDecoder, BlobC = W.Blob,
    DP = W.DOMParser, U8 = W.Uint8Array, AB = W.ArrayBuffer;
  function has(o, k) { return hasOwn.call(o, k); }
  function log() { try { consoleRef.log.apply(consoleRef, arguments); } catch (e) {} }
  function warn(name, e) {
    try { consoleRef.error('[ZT Browser] User script "' + name + '":', e); } catch (x) {}
  }
  function send(o) {
    if (!P) return false;
    try { P.postMessage(stringify(o)); return true; } catch (e) { return false; }
  }

  // ---- Messages from the app ------------------------------------------
  var pending = {}, nextReq = 1, menus = {};
  if (P) {
    P.onmessage = function (e) {
      var m;
      try { m = parse(e.data); } catch (x) { return; }
      if (!m) return;
      if (m.t === 'xhr' && has(pending, m.n)) {
        var done = pending[m.n];
        delete pending[m.n];
        done(m);
      } else if (m.t === 'menu') {
        var cmds = menus[m.s];
        var c = cmds && cmds[m.i];
        if (c) { try { c.fn.call(W); } catch (x) { warn(c.script, x); } }
      }
    };
  }

  function test(rules, url) {
    for (var i = 0; i < rules.length; i++) {
      try { if (new RE(rules[i].s, rules[i].i ? 'i' : '').test(url)) return true; } catch (e) {}
    }
    return false;
  }

  function when(runAt, go) {
    if (runAt === 'document-start') return go();
    if (runAt === 'document-body') {
      if (docRef.body) return go();
      var mo = new W.MutationObserver(function () {
        if (docRef.body) { mo.disconnect(); go(); }
      });
      mo.observe(docRef.documentElement || docRef, { childList: true, subtree: true });
      return;
    }
    var idle = runAt !== 'document-end';
    function ready() { idle ? setT(go, 0) : go(); }
    if (docRef.readyState === 'loading') {
      docRef.addEventListener('DOMContentLoaded', ready, { once: true });
    } else {
      ready();
    }
  }

  function b64ToBytes(b64) {
    var s = atobF(b64), out = new U8(s.length);
    for (var i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }
  function bytesToB64(bytes) {
    var s = '', CH = 0x8000;
    for (var i = 0; i < bytes.length; i += CH) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
    }
    return btoaF(s);
  }
  function charsetOf(type) {
    var m = /charset=([^;]+)/i.exec(type || '');
    return m ? m[1].trim().replace(/^"|"$/g, '') : 'utf-8';
  }

  // ---- The helper functions one script gets -------------------------------
  function api(c) {
    var granted = {}, grants = c.grants || [];
    for (var g = 0; g < grants.length; g++) granted[grants[g].replace(/^GM\./, 'GM_').toLowerCase()] = 1;
    function can(name) { return has(granted, name.toLowerCase()); }
    var values = c.values || {}, listeners = {}, nextListener = 1;
    var info = c.info || {};
    info.scriptHandler = 'ZT Browser';
    info.version = APP;
    info.injectInto = 'page';
    info.isIncognito = !!PRIVATE;

    function getValue(k, d) {
      k = String(k);
      if (!has(values, k)) return d;
      try { return parse(values[k]); } catch (e) { return d; }
    }
    function changed(k, oldRaw, newRaw) {
      for (var id in listeners) {
        if (!has(listeners, id) || listeners[id].k !== k) continue;
        var o, n;
        try { o = oldRaw === undefined ? undefined : parse(oldRaw); } catch (e) {}
        try { n = newRaw === undefined ? undefined : parse(newRaw); } catch (e) {}
        try { listeners[id].fn.call(W, k, o, n, false); } catch (e) { warn(c.name, e); }
      }
    }
    function setValue(k, v) {
      k = String(k);
      var raw = stringify(v);
      if (raw === undefined) return deleteValue(k);
      var old = values[k];
      values[k] = raw;
      if (!PRIVATE) send({ t: 'set', s: c.id, k: k, v: raw });
      if (old !== raw) changed(k, old, raw);
    }
    function deleteValue(k) {
      k = String(k);
      if (!has(values, k)) return;
      var old = values[k];
      delete values[k];
      if (!PRIVATE) send({ t: 'del', s: c.id, k: k });
      changed(k, old, undefined);
    }
    function listValues() { return keysOf(values); }
    function getValues(ks) {
      var out = {};
      if (ks && typeof ks === 'object' && !(ks instanceof W.Array)) {
        for (var k in ks) if (has(ks, k)) out[k] = getValue(k, ks[k]);
      } else {
        ks = ks || keysOf(values);
        for (var i = 0; i < ks.length; i++) if (has(values, ks[i])) out[ks[i]] = getValue(ks[i]);
      }
      return out;
    }
    function setValues(o) { for (var k in o) if (has(o, k)) setValue(k, o[k]); }
    function deleteValues(ks) { for (var i = 0; i < ks.length; i++) deleteValue(ks[i]); }
    function addValueChangeListener(k, fn) {
      var id = nextListener++;
      listeners[id] = { k: String(k), fn: fn };
      return id;
    }
    function removeValueChangeListener(id) { delete listeners[id]; }

    function addStyle(css) {
      var s = docRef.createElement('style');
      s.textContent = String(css);
      (docRef.head || docRef.documentElement).appendChild(s);
      return s;
    }
    function addElement(parent, tag, attrs) {
      if (typeof parent === 'string') { attrs = tag; tag = parent; parent = null; }
      var el = docRef.createElement(tag);
      if (attrs) {
        for (var a in attrs) {
          if (!has(attrs, a)) continue;
          if (a === 'textContent') el.textContent = attrs[a];
          else el.setAttribute(a, attrs[a]);
        }
      }
      (parent || docRef.head || docRef.body || docRef.documentElement).appendChild(el);
      return el;
    }

    var res = c.resources || {};
    function getResourceText(name) {
      var r = res[name];
      if (!r) return null;
      try { return new TD(charsetOf(r.mime)).decode(b64ToBytes(r.data)); } catch (e) { return atobF(r.data); }
    }
    function getResourceURL(name) {
      var r = res[name];
      return r ? 'data:' + (r.mime || 'application/octet-stream') + ';base64,' + r.data : null;
    }

    function xmlhttpRequest(d) {
      d = d || {};
      var n = nextReq++, aborted = false, ctx = d.context;
      var url;
      try { url = new W.URL(d.url, W.location.href).href; } catch (e) { url = String(d.url); }
      var msg = {
        t: 'xhr', s: c.id, n: n, method: String(d.method || 'GET').toUpperCase(), url: url,
        headers: d.headers || {}, timeout: d.timeout || 0, anonymous: !!d.anonymous,
      };
      var body = d.data;
      if (body != null) {
        if (typeof body === 'string') msg.body = body;
        else if (body instanceof W.URLSearchParams) msg.body = body.toString();
        else if (body instanceof AB) msg.b64 = bytesToB64(new U8(body));
        else if (W.ArrayBuffer.isView(body)) msg.b64 = bytesToB64(new U8(body.buffer, body.byteOffset, body.byteLength));
        else if (body instanceof W.FormData) {
          var sp = new W.URLSearchParams();
          body.forEach(function (v, k) { if (typeof v === 'string') sp.append(k, v); });
          msg.body = sp.toString();
          if (!msg.headers['Content-Type'] && !msg.headers['content-type']) {
            msg.headers['Content-Type'] = 'application/x-www-form-urlencoded';
          }
        } else msg.body = String(body);
      }
      function fire(name, r) {
        var f = d[name];
        if (typeof f === 'function') { try { f.call(W, r); } catch (e) { warn(c.name, e); } }
      }
      function response(m) {
        var type = d.responseType || '', mime = d.overrideMimeType || m.type || '';
        var bytes = m.b64 ? b64ToBytes(m.b64) : new U8(0);
        var text = null;
        function textOf() {
          if (text === null) {
            try { text = new TD(charsetOf(mime)).decode(bytes); } catch (e) { text = ''; }
          }
          return text;
        }
        var r = {
          readyState: 4, status: m.status || 0, statusText: m.statusText || '',
          responseHeaders: m.headers || '', finalUrl: m.finalUrl || url, context: ctx,
        };
        defineProp(r, 'responseText', { get: textOf, enumerable: true });
        defineProp(r, 'response', {
          enumerable: true,
          get: function () {
            if (type === 'arraybuffer') return bytes.buffer;
            if (type === 'blob') return new BlobC([bytes], { type: mime });
            if (type === 'json') { try { return parse(textOf()); } catch (e) { return null; } }
            if (type === 'document') {
              try { return new DP().parseFromString(textOf(), /xml/.test(mime) ? 'text/xml' : 'text/html'); } catch (e) { return null; }
            }
            return textOf();
          },
        });
        defineProp(r, 'responseXML', {
          get: function () {
            try { return new DP().parseFromString(textOf(), /xml/.test(mime) ? 'text/xml' : 'text/html'); } catch (e) { return null; }
          },
        });
        return r;
      }
      var promise = new PromiseC(function (ok, fail) {
        if (!can('GM_xmlhttpRequest')) {
          var r0 = { readyState: 4, status: 0, statusText: '', responseText: '', response: null, finalUrl: url, context: ctx, error: 'not granted' };
          setT(function () { fire('onerror', r0); fire('onloadend', r0); fail(r0); }, 0);
          return;
        }
        pending[n] = function (m) {
          if (aborted) return;
          var r = response(m);
          if (m.error) {
            r.error = m.error;
            fire(m.error === 'timeout' ? 'ontimeout' : 'onerror', r);
            fire('onloadend', r);
            fail(r);
          } else {
            fire('onreadystatechange', r);
            fire('onload', r);
            fire('onloadend', r);
            ok(r);
          }
        };
        fire('onloadstart', { readyState: 1, context: ctx });
        if (!send(msg)) pending[n]({ error: 'unavailable' });
      });
      promise.catch(function () {});
      promise.abort = function () {
        if (aborted) return;
        aborted = true;
        delete pending[n];
        send({ t: 'abort', s: c.id, n: n });
        fire('onabort', { readyState: 4, status: 0, context: ctx });
      };
      return promise;
    }

    function openInTab(u, opts) {
      try { u = new W.URL(u, W.location.href).href; } catch (e) {}
      var bg = typeof opts === 'boolean' ? opts : !!(opts && opts.active === false);
      send({ t: 'tab', s: c.id, url: String(u), bg: bg });
      return { closed: false, close: function () {}, onclose: null };
    }
    function setClipboard(data) {
      send({ t: 'clip', s: c.id, text: String(data) });
    }
    function notification(details, title, image, onclick) {
      if (typeof details === 'string') details = { text: details, title: title, onclick: onclick };
      details = details || {};
      send({ t: 'notify', s: c.id, text: String(details.text || ''), title: String(details.title || '') });
      if (typeof details.ondone === 'function') setT(function () { try { details.ondone(); } catch (e) {} }, 0);
    }
    var cmds = {}, nextCmd = 1;
    menus[c.id] = cmds;
    function publishMenu() {
      var list = [];
      for (var i in cmds) if (has(cmds, i)) list[list.length] = { i: +i, n: cmds[i].name };
      if (W.top === W) send({ t: 'menu', s: c.id, cmds: list });
    }
    function registerMenuCommand(name, fn, opts) {
      var id = (opts && typeof opts === 'object' && opts.id) || nextCmd++;
      cmds[id] = { name: String(name), fn: fn, script: c.name };
      publishMenu();
      return id;
    }
    function unregisterMenuCommand(id) { delete cmds[id]; publishMenu(); }

    function promised(fn) {
      return function () {
        var a = arguments;
        return new PromiseC(function (ok, fail) {
          try { ok(fn.apply(null, a)); } catch (e) { fail(e); }
        });
      };
    }

    var all = {
      unsafeWindow: W,
      GM_info: info,
      GM_log: log,
      GM_addStyle: addStyle,
      GM_addElement: addElement,
      GM_getValue: getValue,
      GM_setValue: setValue,
      GM_deleteValue: deleteValue,
      GM_listValues: listValues,
      GM_getValues: getValues,
      GM_setValues: setValues,
      GM_deleteValues: deleteValues,
      GM_addValueChangeListener: addValueChangeListener,
      GM_removeValueChangeListener: removeValueChangeListener,
      GM_getResourceText: getResourceText,
      GM_getResourceURL: getResourceURL,
      GM_xmlhttpRequest: xmlhttpRequest,
      GM_openInTab: openInTab,
      GM_setClipboard: setClipboard,
      GM_notification: notification,
      GM_registerMenuCommand: registerMenuCommand,
      GM_unregisterMenuCommand: unregisterMenuCommand,
    };
    // Given without a @grant, as they can't reach anything the page can't.
    var always = { unsafeWindow: 1, GM_info: 1, GM_log: 1, GM_addStyle: 1, GM_addElement: 1 };
    var GM = { info: info, log: log, addStyle: promised(addStyle), addElement: promised(addElement) };
    if (can('GM_getValue')) GM.getValue = promised(getValue);
    if (can('GM_setValue')) GM.setValue = promised(setValue);
    if (can('GM_deleteValue')) GM.deleteValue = promised(deleteValue);
    if (can('GM_listValues')) GM.listValues = promised(listValues);
    if (can('GM_getValues')) GM.getValues = promised(getValues);
    if (can('GM_setValues')) GM.setValues = promised(setValues);
    if (can('GM_deleteValues')) GM.deleteValues = promised(deleteValues);
    if (can('GM_addValueChangeListener')) GM.addValueChangeListener = promised(addValueChangeListener);
    if (can('GM_removeValueChangeListener')) GM.removeValueChangeListener = promised(removeValueChangeListener);
    if (can('GM_getResourceText')) GM.getResourceText = promised(getResourceText);
    if (can('GM_getResourceURL') || can('GM_getResourceUrl')) {
      GM.getResourceUrl = GM.getResourceURL = promised(getResourceURL);
    }
    if (can('GM_xmlhttpRequest')) GM.xmlHttpRequest = GM.xmlhttpRequest = xmlhttpRequest;
    if (can('GM_openInTab')) GM.openInTab = openInTab;
    if (can('GM_setClipboard')) GM.setClipboard = promised(setClipboard);
    if (can('GM_notification')) GM.notification = promised(notification);
    if (can('GM_registerMenuCommand')) GM.registerMenuCommand = registerMenuCommand;
    if (can('GM_unregisterMenuCommand')) GM.unregisterMenuCommand = unregisterMenuCommand;

    var args = [];
    for (var i = 0; i < ARGS.length; i++) {
      var name = ARGS[i];
      if (name === 'GM') args[i] = GM;
      else if (has(always, name) || can(name)) args[i] = all[name];
      else args[i] = undefined;
    }
    return args;
  }

  var runner = {
    run: function (c, fn) {
      var href = String(W.location.href).split('#')[0];
      if (c.noframes && W.top !== W) return;
      if (!/^(https?|file):/.test(href)) return;
      if (!test(c.inc || [], href) || test(c.exc || [], href)) return;
      var args = api(c);
      when(c.runAt, function () {
        // Not on reader view, which shows the page's text in the app's own
        // layout.
        if (docRef.documentElement && docRef.documentElement.hasAttribute('data-zt-reader')) return;
        try { fn.apply(W, args); } catch (e) { warn(c.name, e); }
      });
    },
  };
  try { defineProp(W, KEY, { value: runner, configurable: true, enumerable: false }); } catch (e) {}
})();
