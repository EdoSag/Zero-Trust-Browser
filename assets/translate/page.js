(function () {
  var K = '__ZTKEY__';
  var S = window[K];
  if (!S) {
    var SKIP = {SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, INPUT: 1, SELECT: 1, OPTION: 1, CODE: 1,
      PRE: 1, KBD: 1, SAMP: 1, VAR: 1, SVG: 1, MATH: 1, CANVAS: 1, IFRAME: 1, TEMPLATE: 1};
    var INLINE = {A: 1, ABBR: 1, B: 1, BDI: 1, BDO: 1, CITE: 1, DATA: 1, DFN: 1, EM: 1, FONT: 1,
      I: 1, MARK: 1, Q: 1, S: 1, SMALL: 1, SPAN: 1, STRONG: 1, SUB: 1, SUP: 1, TIME: 1, U: 1,
      LABEL: 1, DEL: 1, INS: 1};
    var esc = function (t) {
      return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    };
    var skip = function (el) {
      for (var e = el; e && e.nodeType === 1; e = e.parentElement) {
        if (SKIP[e.tagName.toUpperCase()]) return true;
        if (e.getAttribute('translate') === 'no' || e.classList.contains('notranslate')) return true;
        if (e.isContentEditable) return true;
      }
      return false;
    };
    var blockOf = function (el) {
      while (el.parentElement && INLINE[el.tagName.toUpperCase()]) el = el.parentElement;
      return el;
    };
    S = window[K] = {groups: [], done: new WeakSet(), orig: [], dirty: false, on: true, obs: null};
    S.collect = function (max) {
      S.on = true;
      S.dirty = false;
      var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
      var map = new Map(), order = [], t;
      var letters = /[^\s\d!-\/:-@\[-`{-~ -¿ -⁯]/;
      while ((t = w.nextNode())) {
        if (S.done.has(t) || !letters.test(t.data)) continue;
        var p = t.parentElement;
        if (!p || skip(p)) continue;
        var b = blockOf(p), g = map.get(b);
        if (!g) { g = []; map.set(b, g); order.push(b); }
        if (g.length < 200) g.push(t);
      }
      var vh = window.innerHeight || 800;
      var keyed = order.map(function (b, i) {
        var r = b.getBoundingClientRect();
        var seen = r.bottom > 0 && r.top < vh && r.width > 0;
        return {b: b, k: (seen ? 0 : 1) * 1e7 + i};
      }).sort(function (x, y) { return x.k - y.k; });
      var out = [];
      for (var i = 0; i < keyed.length && out.length < max; i++) {
        var nodes = map.get(keyed[i].b);
        var id = S.groups.length;
        S.groups.push(nodes);
        var html = '';
        for (var j = 0; j < nodes.length; j++) {
          S.done.add(nodes[j]);
          html += '<b id="z' + j + '">' + esc(nodes[j].data.replace(/\s+/g, ' ')) + '</b>';
        }
        out.push([id, html]);
      }
      if (!S.obs && window.MutationObserver) {
        // New content (more results, comments...) is translated too.
        S.obs = new MutationObserver(function (records) {
          if (!S.on) return;
          for (var r = 0; r < records.length; r++) {
            if (records[r].addedNodes.length) { S.dirty = true; return; }
          }
        });
        S.obs.observe(document.body, {childList: true, subtree: true});
      }
      return JSON.stringify(out);
    };
    S.apply = function (results) {
      var tpl = document.createElement('template');
      for (var i = 0; i < results.length; i++) {
        var nodes = S.groups[results[i][0]];
        if (!nodes) continue;
        tpl.innerHTML = results[i][1];
        var texts = nodes.map(function () { return ''; });
        var w = document.createTreeWalker(tpl.content, NodeFilter.SHOW_TEXT, null), t, cur = 0;
        while ((t = w.nextNode())) {
          var e = t.parentElement;
          while (e && !/^z\d+$/.test(e.id || '')) e = e.parentElement;
          if (e) cur = Math.min(parseInt(e.id.slice(1), 10), nodes.length - 1);
          texts[cur] += t.data;
        }
        for (var j = 0; j < nodes.length; j++) {
          var n = nodes[j], old = n.data;
          var lead = old.match(/^\s*/)[0], trail = old.match(/\s*$/)[0];
          var next = texts[j].replace(/\s+/g, ' ').trim();
          S.orig.push([n, old]);
          n.data = next ? lead + next + trail : (lead || trail ? ' ' : '');
        }
      }
      return true;
    };
    S.restore = function () {
      S.on = false;
      for (var i = S.orig.length - 1; i >= 0; i--) S.orig[i][0].data = S.orig[i][1];
      S.orig = [];
      S.groups = [];
      S.done = new WeakSet();
      S.dirty = false;
      return true;
    };
  }
  return S;
})()
