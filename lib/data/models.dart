import 'dart:math';

import 'package:zero_trust_core/zero_trust_core.dart';

/// A random item id. Ids are visible to the server, so they never carry the
/// URL (not even hashed: a hash of a URL can be guessed back).
String newItemId() {
  final Random r = Random.secure();
  return List<String>.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

DateTime _ms(Object? v, DateTime fallback) =>
    v is int ? DateTime.fromMillisecondsSinceEpoch(v) : fallback;

/// A saved page. Synced, end-to-end encrypted, like every item.
class Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.createdAt,
    this.folder,
  });

  final String id;
  final String url;
  final String title;
  final DateTime createdAt;

  /// Folder name, or null for the top level.
  final String? folder;

  Bookmark copyWith({String? url, String? title, String? folder}) => Bookmark(
    id: id,
    url: url ?? this.url,
    title: title ?? this.title,
    createdAt: createdAt,
    folder: folder ?? this.folder,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'title': title,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'folder': folder,
  };

  static Bookmark fromJson(String id, Map<String, Object?> j, DateTime at) =>
      Bookmark(
        id: id,
        url: j['url'] as String? ?? '',
        title: j['title'] as String? ?? '',
        createdAt: _ms(j['createdAt'], at),
        folder: j['folder'] as String?,
      );
}

/// One page in the history: the last visit and how often. One item per
/// address, so revisits update it instead of piling up rows.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.url,
    required this.title,
    required this.lastVisit,
    this.visits = 1,
  });

  final String id;
  final String url;
  final String title;
  final DateTime lastVisit;
  final int visits;

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'title': title,
    'lastVisit': lastVisit.millisecondsSinceEpoch,
    'visits': visits,
  };

  static HistoryEntry fromJson(
    String id,
    Map<String, Object?> j,
    DateTime at,
  ) => HistoryEntry(
    id: id,
    url: j['url'] as String? ?? '',
    title: j['title'] as String? ?? '',
    lastVisit: _ms(j['lastVisit'], at),
    visits: (j['visits'] as num?)?.toInt() ?? 1,
  );
}

/// The open tabs of one device, so other devices can show "Tabs from your
/// other devices". Private tabs are never included.
class DeviceTabs {
  const DeviceTabs({
    required this.deviceId,
    required this.deviceName,
    required this.tabs,
    required this.updatedAt,
  });

  final String deviceId;
  final String deviceName;
  final List<({String url, String title})> tabs;
  final DateTime updatedAt;

  String get id => 'tabs-$deviceId';

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'deviceName': deviceName,
    'tabs': <Map<String, String>>[
      for (final t in tabs) <String, String>{'url': t.url, 'title': t.title},
    ],
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static DeviceTabs fromJson(String id, Map<String, Object?> j, DateTime at) =>
      DeviceTabs(
        deviceId: j['deviceId'] as String? ?? id,
        deviceName: j['deviceName'] as String? ?? 'Another device',
        tabs: <({String url, String title})>[
          for (final Object? t in (j['tabs'] as List<Object?>? ?? const []))
            if (t is Map)
              (
                url: t['url'] as String? ?? '',
                title: t['title'] as String? ?? '',
              ),
        ],
        updatedAt: _ms(j['updatedAt'], at),
      );
}

/// A search engine the address bar can use.
class SearchEngine {
  const SearchEngine(this.id, this.name, this.template, this.home);

  final String id;
  final String name;

  /// The search URL, with `{q}` for the query.
  final String template;
  final String home;

  Uri searchUrl(String query) =>
      Uri.parse(template.replaceAll('{q}', Uri.encodeQueryComponent(query)));

  static const SearchEngine duckDuckGo = SearchEngine(
    'duckduckgo',
    'DuckDuckGo',
    'https://duckduckgo.com/?q={q}',
    'https://duckduckgo.com/',
  );

  static const List<SearchEngine> all = <SearchEngine>[
    duckDuckGo,
    SearchEngine(
      'startpage',
      'Startpage',
      'https://www.startpage.com/do/search?q={q}',
      'https://www.startpage.com/',
    ),
    SearchEngine(
      'brave',
      'Brave Search',
      'https://search.brave.com/search?q={q}',
      'https://search.brave.com/',
    ),
    SearchEngine(
      'mojeek',
      'Mojeek',
      'https://www.mojeek.com/search?q={q}',
      'https://www.mojeek.com/',
    ),
    SearchEngine(
      'ecosia',
      'Ecosia',
      'https://www.ecosia.org/search?q={q}',
      'https://www.ecosia.org/',
    ),
    SearchEngine(
      'google',
      'Google',
      'https://www.google.com/search?q={q}',
      'https://www.google.com/',
    ),
    SearchEngine(
      'bing',
      'Bing',
      'https://www.bing.com/search?q={q}',
      'https://www.bing.com/',
    ),
  ];

  static SearchEngine byId(String? id) =>
      all.firstWhere((SearchEngine e) => e.id == id, orElse: () => duckDuckGo);
}

/// Browser settings, synced so every device behaves the same.
class BrowserSettings {
  const BrowserSettings({
    this.searchEngine = 'duckduckgo',
    this.blockTrackers = true,
    this.httpsOnly = true,
    this.allowedSites = const <String>[],
    this.historyDays = 90,
  });

  static const String itemId = 'browser-settings';

  final String searchEngine;
  final bool blockTrackers;
  final bool httpsOnly;

  /// Sites (like `example.com`) where the user turned protection off.
  final List<String> allowedSites;

  /// How long history is kept: 0 keeps none, null keeps it forever.
  final int? historyDays;

  static const List<int?> historyChoices = <int?>[0, 7, 30, 90, 365, null];

  static String historyLabel(int? days) => switch (days) {
    0 => "Don't keep history",
    null => 'Forever',
    7 => '1 week',
    30 => '1 month',
    90 => '3 months',
    365 => '1 year',
    final int d => '$d days',
  };

  SearchEngine get engine => SearchEngine.byId(searchEngine);

  BrowserSettings copyWith({
    String? searchEngine,
    bool? blockTrackers,
    bool? httpsOnly,
    List<String>? allowedSites,
    int? Function()? historyDays,
  }) => BrowserSettings(
    searchEngine: searchEngine ?? this.searchEngine,
    blockTrackers: blockTrackers ?? this.blockTrackers,
    httpsOnly: httpsOnly ?? this.httpsOnly,
    allowedSites: allowedSites ?? this.allowedSites,
    historyDays: historyDays != null ? historyDays() : this.historyDays,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'searchEngine': searchEngine,
    'blockTrackers': blockTrackers,
    'httpsOnly': httpsOnly,
    'allowedSites': allowedSites,
    // -1 is "forever", so a missing key still means the default.
    'historyDays': historyDays ?? -1,
  };

  static BrowserSettings fromJson(
    String id,
    Map<String, Object?> j,
    DateTime at,
  ) {
    final Object? days = j['historyDays'];
    return BrowserSettings(
      searchEngine: j['searchEngine'] as String? ?? 'duckduckgo',
      blockTrackers: j['blockTrackers'] as bool? ?? true,
      httpsOnly: j['httpsOnly'] as bool? ?? true,
      allowedSites: <String>[
        for (final Object? s
            in (j['allowedSites'] as List<Object?>? ?? const []))
          if (s is String) s,
      ],
      historyDays: days is int ? (days < 0 ? null : days) : 90,
    );
  }
}

/// The kinds of items ZT Browser keeps in its synced store.
abstract final class BrowserCollections {
  static final ZtCollection<Bookmark> bookmarks = ZtCollection<Bookmark>(
    kind: 'bookmark',
    fromJson: Bookmark.fromJson,
    toJson: (Bookmark b) => b.toJson(),
    idOf: (Bookmark b) => b.id,
  );

  static final ZtCollection<HistoryEntry> history = ZtCollection<HistoryEntry>(
    kind: 'history',
    fromJson: HistoryEntry.fromJson,
    toJson: (HistoryEntry h) => h.toJson(),
    idOf: (HistoryEntry h) => h.id,
  );

  static final ZtCollection<DeviceTabs> deviceTabs = ZtCollection<DeviceTabs>(
    kind: 'device-tabs',
    fromJson: DeviceTabs.fromJson,
    toJson: (DeviceTabs t) => t.toJson(),
    idOf: (DeviceTabs t) => t.id,
  );

  static final ZtCollection<BrowserSettings> settings =
      ZtCollection<BrowserSettings>(
        kind: 'settings',
        fromJson: BrowserSettings.fromJson,
        toJson: (BrowserSettings s) => s.toJson(),
        idOf: (_) => BrowserSettings.itemId,
      );
}
