/// B41: user scripts in the Tampermonkey / Greasemonkey / Violentmonkey
/// format. This file reads a script's metadata block and turns its site
/// rules (@match, @include, @exclude, @exclude-match) into regular
/// expressions the page side tests against the address. Pure Dart, so
/// tests can run it without a phone.
library;

/// The helper functions ZT Browser gives scripts (see
/// assets/userscripts/runtime.js). Both spellings, GM_x and GM.x.
const Set<String> supportedGrants = <String>{
  'none',
  'unsafeWindow',
  'GM_info',
  'GM_log',
  'GM_addStyle',
  'GM_addElement',
  'GM_getValue',
  'GM_setValue',
  'GM_deleteValue',
  'GM_listValues',
  'GM_getValues',
  'GM_setValues',
  'GM_deleteValues',
  'GM_addValueChangeListener',
  'GM_removeValueChangeListener',
  'GM_getResourceText',
  'GM_getResourceURL',
  'GM_xmlhttpRequest',
  'GM_openInTab',
  'GM_setClipboard',
  'GM_notification',
  'GM_registerMenuCommand',
  'GM_unregisterMenuCommand',
  'GM.info',
  'GM.log',
  'GM.addStyle',
  'GM.addElement',
  'GM.getValue',
  'GM.setValue',
  'GM.deleteValue',
  'GM.listValues',
  'GM.getValues',
  'GM.setValues',
  'GM.deleteValues',
  'GM.addValueChangeListener',
  'GM.removeValueChangeListener',
  'GM.getResourceText',
  'GM.getResourceUrl',
  'GM.getResourceURL',
  'GM.xmlHttpRequest',
  'GM.xmlhttpRequest',
  'GM.openInTab',
  'GM.setClipboard',
  'GM.notification',
  'GM.registerMenuCommand',
  'GM.unregisterMenuCommand',
  'window.close',
  'window.focus',
};

/// Grants that let a script send data to other sites.
const Set<String> networkGrants = <String>{
  'GM_xmlhttpRequest',
  'GM.xmlHttpRequest',
  'GM.xmlhttpRequest',
};

/// What a script asks for, grouped for the install screen.
enum ScriptPermission {
  /// Keeps its own data on this phone (GM_setValue...).
  storage,

  /// Sends requests to other sites (GM_xmlhttpRequest).
  network,

  /// Opens new tabs.
  tabs,

  /// Writes to the clipboard.
  clipboard,

  /// Shows notifications.
  notifications,

  /// Adds commands to the browser's menu.
  menu,
}

ScriptPermission? _permissionOf(String grant) {
  final String g = grant.replaceFirst('GM.', 'GM_').toLowerCase();
  if (g.contains('value')) return ScriptPermission.storage;
  if (g.contains('xmlhttprequest')) return ScriptPermission.network;
  if (g == 'gm_openintab') return ScriptPermission.tabs;
  if (g == 'gm_setclipboard') return ScriptPermission.clipboard;
  if (g == 'gm_notification') return ScriptPermission.notifications;
  if (g.contains('menucommand')) return ScriptPermission.menu;
  return null;
}

/// A rule for addresses: a regular expression the page side runs with
/// `new RegExp(source, ignoreCase ? 'i' : '')`.
class UrlRule {
  const UrlRule(this.source, {this.ignoreCase = false});

  final String source;
  final bool ignoreCase;

  bool test(String url) =>
      RegExp(source, caseSensitive: !ignoreCase).hasMatch(url);

  Map<String, Object?> toJson() => <String, Object?>{
    's': source,
    if (ignoreCase) 'i': true,
  };
}

/// The metadata block of a user script (`// ==UserScript==` ...
/// `// ==/UserScript==`).
class UserScriptMeta {
  UserScriptMeta._(this._values);

  final Map<String, List<String>> _values;

  /// Null when [code] has no metadata block or no @name.
  static UserScriptMeta? parse(String code) {
    final RegExpMatch? block = RegExp(
      r'//\s*==UserScript==([\s\S]*?)//\s*==/UserScript==',
    ).firstMatch(code);
    if (block == null) return null;
    final Map<String, List<String>> values = <String, List<String>>{};
    final RegExp line = RegExp(r'^\s*//\s*@([\w:.\-]+)(?:\s+(.*?))?\s*$');
    for (final String raw in block.group(1)!.split('\n')) {
      final RegExpMatch? m = line.firstMatch(raw);
      if (m == null) continue;
      values.putIfAbsent(m.group(1)!, () => <String>[]).add(m.group(2) ?? '');
    }
    final UserScriptMeta meta = UserScriptMeta._(values);
    return meta.name.isEmpty ? null : meta;
  }

  String? _one(String key) {
    final List<String>? v = _values[key];
    if (v == null || v.isEmpty) return null;
    final String s = v.first.trim();
    return s.isEmpty ? null : s;
  }

  List<String> _all(String key) => <String>[
    for (final String v in _values[key] ?? const <String>[])
      if (v.trim().isNotEmpty) v.trim(),
  ];

  String get name => _one('name') ?? '';

  /// The name in [locale] ("he") when the script has one (@name:he).
  String nameIn(String locale) => _one('name:$locale') ?? name;
  String? get namespace => _one('namespace');
  String? get version => _one('version');
  String? get description => _one('description');
  String? descriptionIn(String locale) =>
      _one('description:$locale') ?? description;
  String? get author => _one('author');
  String? get homepage =>
      _one('homepageURL') ??
      _one('homepage') ??
      _one('website') ??
      _one('source');
  String? get icon =>
      _one('icon') ?? _one('iconURL') ?? _one('defaulticon') ?? _one('icon64');
  String? get updateUrl => _one('updateURL');
  String? get downloadUrl => _one('downloadURL');

  List<String> get matches => _all('match');
  List<String> get includes => _all('include');
  List<String> get excludes => _all('exclude');
  List<String> get excludeMatches => _all('exclude-match');
  List<String> get requires => _all('require');
  List<String> get connects => _all('connect');

  /// `@resource name url`, in order.
  Map<String, String> get resources => <String, String>{
    for (final String v in _all('resource'))
      if (RegExp(r'^(\S+)\s+(\S+)').firstMatch(v) case final RegExpMatch m)
        m.group(1)!: m.group(2)!,
  };

  List<String> get grants => _all('grant');

  /// document-start, document-body, document-end or document-idle (the
  /// default). context-menu scripts aren't supported and never run.
  String get runAt {
    final String? v = _one('run-at')?.toLowerCase();
    const List<String> known = <String>[
      'document-start',
      'document-body',
      'document-end',
      'document-idle',
      'context-menu',
    ];
    return known.contains(v) ? v! : 'document-idle';
  }

  bool get noFrames => _values.containsKey('noframes');

  /// Grants this browser doesn't have; the script may still work.
  List<String> get unsupportedGrants => <String>[
    for (final String g in grants)
      if (!supportedGrants.contains(g)) g,
  ];

  Set<ScriptPermission> get permissions => <ScriptPermission>{
    for (final String g in grants)
      if (_permissionOf(g) case final ScriptPermission p) p,
  };

  bool get usesNetwork => grants.any(networkGrants.contains);

  /// The raw metadata block, for GM_info.scriptMetaStr.
  Map<String, List<String>> get values => _values;

  // ---- Sites -------------------------------------------------------------

  List<UrlRule> get includeRules {
    final List<UrlRule> rules = <UrlRule>[
      for (final String m in matches)
        if (matchPatternRule(m) case final UrlRule r) r,
      for (final String i in includes)
        if (globRule(i) case final UrlRule r) r,
    ];
    // A script with no site rules runs everywhere, as in Tampermonkey.
    if (matches.isEmpty && includes.isEmpty) {
      return const <UrlRule>[UrlRule('^(?:https?|file)://')];
    }
    return rules;
  }

  List<UrlRule> get excludeRules => <UrlRule>[
    for (final String m in excludeMatches)
      if (matchPatternRule(m) case final UrlRule r) r,
    for (final String e in excludes)
      if (globRule(e) case final UrlRule r) r,
  ];

  /// Whether the script runs on [url] (without its #fragment).
  bool runsOn(String url) {
    final String u = url.split('#').first;
    return includeRules.any((UrlRule r) => r.test(u)) &&
        !excludeRules.any((UrlRule r) => r.test(u));
  }

  /// The sites the script runs on, as people read them ("example.com",
  /// "*.example.com"), or null when it runs on every site.
  List<String>? get sites {
    if (matches.isEmpty && includes.isEmpty) return null;
    final Set<String> out = <String>{};
    for (final String p in <String>[...matches, ...includes]) {
      final String? host = hostOfPattern(p);
      if (host == null) return null;
      out.add(host);
    }
    return out.toList();
  }

  /// Sites the script may send requests to (@connect), or null for any
  /// site. Empty when it can't send requests at all.
  List<String>? get connectSites {
    if (!usesNetwork) return const <String>[];
    final List<String> c = connects;
    if (c.isEmpty || c.contains('*')) return null;
    return c;
  }
}

String _escape(String s) => s.replaceAllMapped(
  RegExp(r'[.*+?^${}()|[\]\\/]'),
  (Match m) => '\\${m.group(0)}',
);

/// A Chrome-style match pattern (`*://*.example.com/path*`,
/// `<all_urls>`) as a rule, or null when it isn't one.
UrlRule? matchPatternRule(String pattern) {
  final String p = pattern.trim();
  if (p == '<all_urls>' || p == '*') {
    return const UrlRule('^(?:https?|file)://');
  }
  final RegExpMatch? m = RegExp(
    r'^(\*|https?|file|ftp)://([^/]*)(/.*)?$',
  ).firstMatch(p);
  if (m == null) return null;
  final String scheme = m.group(1) == '*' ? 'https?' : _escape(m.group(1)!);
  final String host = m.group(2)!;
  final String path = m.group(3) ?? '/*';
  String hostRe;
  if (host == '*' || (host.isEmpty && m.group(1) == 'file')) {
    hostRe = '[^/]*';
  } else if (host.startsWith('*.')) {
    hostRe = '(?:[^/]*\\.)?${_escape(host.substring(2))}';
  } else if (host.contains('*')) {
    return null;
  } else {
    hostRe = _escape(host);
  }
  final String pathRe = path.split('*').map(_escape).join('.*');
  return UrlRule('^$scheme://$hostRe(?::\\d+)?$pathRe\$');
}

/// A Greasemonkey @include / @exclude: a glob with `*` (and `.tld` for any
/// top-level domain), or a /regular expression/.
UrlRule? globRule(String pattern) {
  final String p = pattern.trim();
  if (p.isEmpty) return null;
  final RegExpMatch? re = RegExp(r'^/(.+)/(i?)$').firstMatch(p);
  if (re != null) {
    try {
      RegExp(re.group(1)!);
    } on FormatException {
      return null;
    }
    return UrlRule(re.group(1)!, ignoreCase: true);
  }
  if (p == '*') return const UrlRule('^(?:https?|file)://');
  final String body = p
      .split('*')
      .map(
        (String part) => _escape(
          part,
        ).replaceAll(r'\.tld', '\u0000'), // placeholder, restored below
      )
      .join('.*')
      .replaceAll('\u0000', r'\.[a-z]{2,}(?:\.[a-z]{2,})?');
  return UrlRule('^$body\$', ignoreCase: true);
}

/// The host part of a @match or @include as shown to people, or null when
/// the pattern covers every site.
String? hostOfPattern(String pattern) {
  final String p = pattern.trim();
  if (p == '<all_urls>' || p == '*') return null;
  if (p.startsWith('/') && p.endsWith('/')) {
    // A regular expression: show it as written, minus the slashes.
    final String inner = p.substring(1, p.length - 1);
    final RegExpMatch? lit = RegExp(
      r'^\^?https?\??(?:\\?:)?\\?/\\?/((?:[\w-]+\\?\.)+[a-z]{2,})',
    ).firstMatch(inner);
    return lit?.group(1)?.replaceAll(r'\', '');
  }
  final int scheme = p.indexOf('://');
  String host = (scheme >= 0 ? p.substring(scheme + 3) : p).split('/').first;
  host = host.replaceFirst(RegExp(r':\d+$'), '');
  // "example.com*" (a glob running into the path).
  if (host.length > 1) host = host.replaceFirst(RegExp(r'\*+$'), '');
  if (host.isEmpty || host == '*' || RegExp(r'^\*+\.?\*?$').hasMatch(host)) {
    return null;
  }
  // "*example.com" or "*.example.com": the site and its subdomains.
  if (host.startsWith('*') && !host.startsWith('*.')) {
    host = '*.${host.substring(1).replaceFirst(RegExp(r'^\.'), '')}';
  }
  // A host that is mostly wildcards (www.*.com) covers too much to name.
  if (host.replaceAll(RegExp(r'[*.]'), '').length < 3) return null;
  return host;
}

/// Compares two @version strings: negative when [a] is older than [b].
int compareVersions(String? a, String? b) {
  if (a == b) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  final List<String> x = a.split(RegExp(r'[.\-+]'));
  final List<String> y = b.split(RegExp(r'[.\-+]'));
  for (int i = 0; i < x.length || i < y.length; i++) {
    final String p = i < x.length ? x[i] : '0';
    final String q = i < y.length ? y[i] : '0';
    final int? pn = int.tryParse(p);
    final int? qn = int.tryParse(q);
    final int c = (pn != null && qn != null)
        ? pn.compareTo(qn)
        : p.compareTo(q);
    if (c != 0) return c;
  }
  return 0;
}
