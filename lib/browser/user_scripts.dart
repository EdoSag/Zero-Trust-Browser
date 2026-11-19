import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/user_script.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// B41: the user's scripts, in their order.
final userScriptsProvider = StreamProvider<List<UserScript>>((ref) async* {
  final LocalItemStore store = await ref.watch(ztLocalStoreProvider.future);
  yield* BrowserCollections.userScripts
      .watch(store as ZtLocalStore)
      .map((List<UserScript> l) => l..sort(UserScript.compare));
});

final userScriptsServiceProvider = Provider<UserScriptsService>(
  (ref) => UserScriptsService(ref),
);

/// Why a script couldn't be added.
enum ScriptProblem {
  /// No `// ==UserScript==` block with a @name.
  notAScript,

  /// The address couldn't be loaded.
  download,

  /// A file it @requires or a @resource couldn't be loaded.
  dependency,

  /// Too large to sync (the script with its files).
  tooLarge,
}

class ScriptException implements Exception {
  const ScriptException(this.problem, [this.detail]);
  final ScriptProblem problem;

  /// The address that failed, for [ScriptProblem.dependency].
  final String? detail;

  @override
  String toString() => 'ScriptException($problem, $detail)';
}

/// A script fetched and read, with its files, waiting for the user's yes.
class PreparedScript {
  const PreparedScript({
    required this.code,
    required this.meta,
    required this.requires,
    required this.resources,
    this.sourceUrl,
    this.existing,
  });

  final String code;
  final UserScriptMeta meta;
  final Map<String, String> requires;
  final Map<String, ScriptResource> resources;
  final String? sourceUrl;

  /// The installed script this one replaces (same name and namespace, or
  /// the one being updated or edited).
  final UserScript? existing;

  /// Sites it runs on that the installed version didn't.
  List<String> get newSites {
    final List<String>? now = meta.sites;
    final UserScriptMeta? old = existing?.meta;
    if (old == null || now == null) return const <String>[];
    final List<String>? before = old.sites;
    if (before == null) return const <String>[];
    return now.where((String s) => !before.contains(s)).toList();
  }

  /// It now runs on every site; the installed version didn't.
  bool get newlyEverywhere {
    final UserScriptMeta? old = existing?.meta;
    return old != null && old.sites != null && meta.sites == null;
  }

  /// Permissions the installed version didn't have.
  Set<ScriptPermission> get newPermissions {
    final UserScriptMeta? old = existing?.meta;
    if (old == null) return const <ScriptPermission>{};
    return meta.permissions.difference(old.permissions);
  }

  /// Sites it may send data to that the installed version couldn't.
  List<String> get newConnectSites {
    final UserScriptMeta? old = existing?.meta;
    if (old == null) return const <String>[];
    final List<String>? now = meta.connectSites;
    final List<String>? before = old.connectSites;
    if (now == null || before == null) return const <String>[];
    return now.where((String s) => !before.contains(s)).toList();
  }

  bool get newlyConnectsAnywhere {
    final UserScriptMeta? old = existing?.meta;
    return old != null && old.connectSites != null && meta.connectSites == null;
  }
}

/// Synced items are limited to 1 MB encrypted; leave room for that.
const int maxScriptBytes = 700 * 1024;

/// Adds, updates and removes scripts, and hands them to the web engine.
class UserScriptsService {
  UserScriptsService(this.ref, {http.Client? client})
    : _client = client ?? http.Client();

  final Ref ref;
  final http.Client _client;

  List<UserScript> get _all =>
      ref.read(userScriptsProvider).value ?? const <UserScript>[];

  // ---- Fetching ------------------------------------------------------------

  Future<http.Response> _get(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const ScriptException(ScriptProblem.download);
    }
    final http.Response r = await _client
        .get(uri)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw const ScriptException(ScriptProblem.download);
    }
    if (r.bodyBytes.length > maxScriptBytes) {
      throw const ScriptException(ScriptProblem.tooLarge);
    }
    return r;
  }

  /// The script at [url], as text.
  Future<String> download(String url) async {
    try {
      final http.Response r = await _get(url);
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } on ScriptException {
      rethrow;
    } on Object {
      throw const ScriptException(ScriptProblem.download);
    }
  }

  /// Reads [code] and fetches the files it names, for the install screen.
  /// [existing] is the script it updates or edits, if any; otherwise one
  /// with the same name and namespace counts as that.
  Future<PreparedScript> prepare(
    String code, {
    String? sourceUrl,
    UserScript? existing,
  }) async {
    final UserScriptMeta? meta = UserScriptMeta.parse(code);
    if (meta == null) throw const ScriptException(ScriptProblem.notAScript);
    final UserScript? same =
        existing ??
        _all
            .where(
              (UserScript u) =>
                  u.meta?.name == meta.name &&
                  u.meta?.namespace == meta.namespace,
            )
            .firstOrNull;
    final Map<String, String> requires = <String, String>{};
    for (final String url in meta.requires) {
      // Already fetched for the installed version: same address, same file
      // (scripts pin versions in the address).
      final String? kept = same?.requires[url];
      if (kept != null) {
        requires[url] = kept;
        continue;
      }
      try {
        final http.Response r = await _get(url);
        requires[url] = utf8.decode(r.bodyBytes, allowMalformed: true);
      } on Object {
        throw ScriptException(ScriptProblem.dependency, url);
      }
    }
    final Map<String, ScriptResource> resources = <String, ScriptResource>{};
    for (final MapEntry<String, String> e in meta.resources.entries) {
      final ScriptResource? kept = same?.resources[e.key];
      if (kept != null && kept.url == e.value) {
        resources[e.key] = kept;
        continue;
      }
      if (e.value.startsWith('data:')) {
        final UriData? d = Uri.tryParse(e.value)?.data;
        if (d == null) throw ScriptException(ScriptProblem.dependency, e.value);
        resources[e.key] = ScriptResource(
          url: e.value,
          mime: d.mimeType,
          data: base64.encode(d.contentAsBytes()),
        );
        continue;
      }
      try {
        final http.Response r = await _get(e.value);
        resources[e.key] = ScriptResource(
          url: e.value,
          mime:
              r.headers['content-type']?.split(';').first.trim() ??
              mimeOf(e.value),
          data: base64.encode(r.bodyBytes),
        );
      } on Object {
        throw ScriptException(ScriptProblem.dependency, e.value);
      }
    }
    final PreparedScript p = PreparedScript(
      code: code,
      meta: meta,
      requires: requires,
      resources: resources,
      sourceUrl: sourceUrl ?? same?.sourceUrl,
      existing: same,
    );
    if (sizeOf(p) > maxScriptBytes) {
      throw const ScriptException(ScriptProblem.tooLarge);
    }
    return p;
  }

  static int sizeOf(PreparedScript p) =>
      utf8.encode(p.code).length +
      p.requires.values.fold<int>(0, (int n, String c) => n + c.length) +
      p.resources.values.fold<int>(
        0,
        (int n, ScriptResource r) => n + r.data.length,
      );

  /// A newer version from the script's update address, or null when there
  /// is none. Never installed without the user seeing it first.
  Future<PreparedScript?> checkForUpdate(UserScript s) async {
    final String? url = s.updateUrl;
    if (url == null) return null;
    String code = await download(url);
    UserScriptMeta? meta = UserScriptMeta.parse(code);
    // A .meta.js update address has only the metadata block: the script
    // itself is at @downloadURL.
    final String? full = meta?.downloadUrl ?? s.meta?.downloadUrl;
    if (meta != null &&
        url.endsWith('.meta.js') &&
        full != null &&
        compareVersions(s.meta?.version, meta.version) < 0) {
      code = await download(full);
      meta = UserScriptMeta.parse(code);
    }
    if (meta == null) throw const ScriptException(ScriptProblem.notAScript);
    final bool newer = compareVersions(s.meta?.version, meta.version) < 0;
    if (!newer) return null;
    return prepare(
      code,
      sourceUrl: s.sourceUrl ?? meta.downloadUrl ?? url,
      existing: s,
    );
  }

  // ---- Saving ----------------------------------------------------------------

  Future<UserScript> install(PreparedScript p) async {
    final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
    final SyncController sync = ref.read(ztSyncControllerProvider.notifier);
    final DateTime now = DateTime.now();
    final UserScript? old = p.existing;
    final UserScript s = old != null
        ? old.copyWith(
            code: p.code,
            updatedAt: now,
            requires: p.requires,
            resources: p.resources,
            sourceUrl: () => p.sourceUrl,
          )
        : UserScript(
            id: newItemId(),
            code: p.code,
            installedAt: now,
            updatedAt: now,
            sourceUrl: p.sourceUrl,
            requires: p.requires,
            resources: p.resources,
          );
    await BrowserCollections.userScripts.save(sync, store, s);
    return s;
  }

  Future<void> save(UserScript s) async {
    final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
    await BrowserCollections.userScripts.save(
      ref.read(ztSyncControllerProvider.notifier),
      store,
      s,
    );
  }

  Future<void> delete(UserScript s) async {
    await BrowserCollections.userScripts.delete(
      ref.read(ztSyncControllerProvider.notifier),
      s.id,
    );
    await ref.read(browserEngineProvider).forgetUserScript(s.id);
  }

  /// Hands the enabled scripts to the web engine.
  Future<void> push(List<UserScript> scripts) =>
      ref.read(browserEngineProvider).setUserScripts(toEngine(scripts));
}

/// What the web engine needs of each enabled script.
List<Map<String, Object?>> toEngine(List<UserScript> scripts) {
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  for (final UserScript s in scripts) {
    if (!s.enabled) continue;
    final UserScriptMeta? m = s.meta;
    if (m == null || m.runAt == 'context-menu') continue;
    final List<String> grants = m.grants;
    final String body = <String>[
      for (final String url in m.requires)
        if (s.requires[url] case final String c) c,
      s.code,
    ].join('\n;\n');
    final Map<String, Object?> info = <String, Object?>{
      'script': <String, Object?>{
        'name': m.name,
        'namespace': m.namespace,
        'version': m.version,
        'description': m.description,
        'author': m.author,
        'homepage': m.homepage,
        'icon': m.icon,
        'matches': m.matches,
        'includes': m.includes,
        'excludes': m.excludes,
        'exclude-match': m.excludeMatches,
        'grant': grants,
        'connects': m.connects,
        'require': m.requires,
        'resources': <Map<String, String>>[
          for (final MapEntry<String, String> e in m.resources.entries)
            <String, String>{'name': e.key, 'url': e.value},
        ],
        'run-at': m.runAt,
        'noframes': m.noFrames,
        'updateURL': m.updateUrl,
        'downloadURL': m.downloadUrl,
        'lastModified': s.updatedAt.millisecondsSinceEpoch,
      },
      'scriptMetaStr': metaBlockOf(s.code),
      'scriptWillUpdate': false,
    };
    out.add(<String, Object?>{
      'id': s.id,
      'name': m.name,
      'code': body,
      'grants': grants,
      'connects': m.connects,
      'allowPrivate': s.allowPrivate,
      'config': jsonEncode(<String, Object?>{
        'name': m.name,
        'inc': <Object?>[for (final UrlRule r in m.includeRules) r.toJson()],
        'exc': <Object?>[for (final UrlRule r in m.excludeRules) r.toJson()],
        'runAt': m.runAt,
        'noframes': m.noFrames,
        'grants': grants,
        'resources': <String, Object?>{
          for (final MapEntry<String, ScriptResource> e in s.resources.entries)
            e.key: <String, String>{'mime': e.value.mime, 'data': e.value.data},
        },
        'info': info,
      }),
    });
  }
  return out;
}

/// The metadata block as written, for GM_info.scriptMetaStr.
String metaBlockOf(String code) =>
    RegExp(
      r'//\s*==UserScript==[\s\S]*?//\s*==/UserScript==',
    ).firstMatch(code)?.group(0) ??
    '';

/// A file type from an address's extension.
String mimeOf(String url) {
  final String path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  const Map<String, String> types = <String, String>{
    '.css': 'text/css',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.webp': 'image/webp',
    '.html': 'text/html',
    '.txt': 'text/plain',
    '.woff2': 'font/woff2',
  };
  for (final MapEntry<String, String> e in types.entries) {
    if (path.endsWith(e.key)) return e.value;
  }
  return 'application/octet-stream';
}
