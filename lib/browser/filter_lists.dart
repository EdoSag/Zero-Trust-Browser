import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// Hosts a filter list blocks. Understands the common formats:
///
/// - hosts files: `0.0.0.0 ads.example.com` or `127.0.0.1 ads.example.com`
/// - plain domain lists: `ads.example.com`
/// - AdBlock domain rules: `||ads.example.com^` (with no path; rules with
///   options or a path, cosmetic rules and exceptions are skipped, since
///   ZT Browser blocks by host)
///
/// Comments (`#`, `!`, `[Adblock...]`) and localhost entries are ignored.
Set<String> parseFilterList(String text, {int max = maxHostsPerList}) {
  final Set<String> out = <String>{};
  for (final String raw in const LineSplitter().convert(text)) {
    if (out.length >= max) break;
    String line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    if (line.startsWith('[')) continue;
    final int hash = line.indexOf('#');
    if (hash >= 0) {
      // "host # comment" in hosts files; "##" cosmetic rules are skipped.
      if (line.contains('##') || line.contains('#@#') || line.contains('#?#')) {
        continue;
      }
      line = line.substring(0, hash).trim();
    }
    String? host;
    if (line.startsWith('||')) {
      final String rule = line.substring(2);
      // Only whole-host rules: "||host^" (and "||host^$third-party", which
      // blocks at least as much as ZT Browser's third-party handling).
      final RegExpMatch? m = RegExp(
        r'^([a-z0-9.-]+)\^(\$third-party)?$',
        caseSensitive: false,
      ).firstMatch(rule);
      if (m == null) continue;
      host = m.group(1);
    } else if (line.startsWith('@@') ||
        line.contains(r'$') ||
        line.contains('/')) {
      continue;
    } else {
      final List<String> parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2 &&
          (parts[0] == '0.0.0.0' ||
              parts[0] == '127.0.0.1' ||
              parts[0] == '::' ||
              parts[0] == '::1')) {
        host = parts[1];
      } else if (parts.length == 1) {
        host = parts[0];
      }
    }
    final String? clean = host == null ? null : cleanHostRule(host);
    if (clean == null ||
        clean == 'localhost' ||
        clean.endsWith('.localdomain') ||
        clean == 'local' ||
        !clean.contains('.')) {
      continue;
    }
    out.add(clean);
  }
  return out;
}

/// More than any common list has; a typo'd URL to a huge file stays bounded.
const int maxHostsPerList = 400000;
const int _maxBytes = 30 * 1024 * 1024;

/// One extra list, as last downloaded.
class FilterListStatus {
  const FilterListStatus({this.hosts = 0, this.fetchedAt, this.error});

  final int hosts;
  final DateTime? fetchedAt;

  /// Why the last download failed, or null.
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
    'hosts': hosts,
    if (fetchedAt != null) 'fetchedAt': fetchedAt!.millisecondsSinceEpoch,
    if (error != null) 'error': error,
  };

  static FilterListStatus fromJson(Object? j) {
    if (j is! Map) return const FilterListStatus();
    final Object? at = j['fetchedAt'];
    return FilterListStatus(
      hosts: (j['hosts'] as num?)?.toInt() ?? 0,
      fetchedAt: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      error: j['error'] as String?,
    );
  }
}

/// B30: the user's own block and allow rules, and extra filter lists by
/// address. The lists are downloaded straight from the address the user
/// gave (nothing goes through ZT servers), weekly, and kept on this phone
/// as one file of hosts that the engine reads.
class UserBlockRules {
  UserBlockRules(
    this.ref, {
    http.Client? client,
    Future<Directory> Function()? dir,
  }) : _client = client ?? http.Client(),
       _dir = dir ?? getApplicationSupportDirectory;

  final Ref ref;
  final http.Client _client;
  final Future<Directory> Function() _dir;
  static const String _statusKey = 'browser_filter_lists';
  static const Duration refreshEvery = Duration(days: 7);

  Future<File> _listFile(String url) async {
    final Directory d = Directory('${(await _dir()).path}/filter-lists');
    await d.create(recursive: true);
    // The address, made into a safe file name.
    final String name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return File(
      '${d.path}/${name.length > 120 ? name.substring(0, 120) : name}.txt',
    );
  }

  Future<File> _combinedFile() async =>
      File('${(await _dir()).path}/filter-lists/all-hosts.txt');

  Future<Map<String, FilterListStatus>> statuses() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String? raw = p.getString(_statusKey);
    if (raw == null) return <String, FilterListStatus>{};
    try {
      final Map<String, Object?> m = jsonDecode(raw) as Map<String, Object?>;
      return <String, FilterListStatus>{
        for (final MapEntry<String, Object?> e in m.entries)
          e.key: FilterListStatus.fromJson(e.value),
      };
    } on Object {
      return <String, FilterListStatus>{};
    }
  }

  Future<void> _saveStatuses(Map<String, FilterListStatus> s) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(
      _statusKey,
      jsonEncode(<String, Object?>{
        for (final MapEntry<String, FilterListStatus> e in s.entries)
          e.key: e.value.toJson(),
      }),
    );
  }

  /// Downloads one list now. Returns how many hosts it has, or throws.
  Future<int> fetch(String url) async {
    final Map<String, FilterListStatus> all = await statuses();
    try {
      final http.Request req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true;
      final http.StreamedResponse res = await _client
          .send(req)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res.stream) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBytes) throw const HttpException('too large');
      }
      final Set<String> hosts = parseFilterList(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (hosts.isEmpty) throw const FormatException('no hosts');
      await (await _listFile(url)).writeAsString(hosts.join('\n'));
      all[url] = FilterListStatus(
        hosts: hosts.length,
        fetchedAt: DateTime.now(),
      );
      await _saveStatuses(all);
      return hosts.length;
    } on Object catch (e) {
      final FilterListStatus old = all[url] ?? const FilterListStatus();
      all[url] = FilterListStatus(
        hosts: old.hosts,
        fetchedAt: old.fetchedAt,
        error: e is FormatException ? 'empty' : 'failed',
      );
      await _saveStatuses(all);
      rethrow;
    }
  }

  /// Downloads lists not fetched for a week (or never), then applies.
  Future<void> refreshIfDue({DateTime? now}) async {
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final Map<String, FilterListStatus> all = await statuses();
    final DateTime t = now ?? DateTime.now();
    for (final String url in s.filterLists) {
      final DateTime? at = all[url]?.fetchedAt;
      if (at == null || t.difference(at) > refreshEvery) {
        try {
          await fetch(url);
        } on Object {
          // Kept for next time; the last good copy stays in use.
        }
      }
    }
    await apply();
  }

  /// Hands the rules and the lists' hosts to the engine. Lists the user
  /// removed are deleted from the phone.
  Future<void> apply() async {
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final File combined = await _combinedFile();
    final Set<String> hosts = <String>{};
    for (final String url in s.filterLists) {
      final File f = await _listFile(url);
      if (await f.exists()) {
        hosts.addAll(const LineSplitter().convert(await f.readAsString()));
      }
    }
    // Forget removed lists.
    final Map<String, FilterListStatus> all = await statuses();
    final List<String> gone = <String>[
      for (final String url in all.keys)
        if (!s.filterLists.contains(url)) url,
    ];
    for (final String url in gone) {
      all.remove(url);
      final File f = await _listFile(url);
      if (await f.exists()) await f.delete();
    }
    if (gone.isNotEmpty) await _saveStatuses(all);
    String? path;
    if (hosts.isNotEmpty) {
      await combined.parent.create(recursive: true);
      await combined.writeAsString(hosts.join('\n'));
      path = combined.path;
    } else if (await combined.exists()) {
      await combined.delete();
    }
    await ref
        .read(browserEngineProvider)
        .setUserRules(
          blocked: s.blockedHosts,
          allowed: s.unblockedHosts,
          listsFile: path,
        );
  }
}

final userBlockRulesProvider = Provider<UserBlockRules>(UserBlockRules.new);
