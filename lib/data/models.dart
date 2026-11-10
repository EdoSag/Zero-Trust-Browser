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

/// One open tab as saved in the account: enough to reopen it, its group,
/// and when it was last looked at (to close tabs left unused).
class SavedTab {
  const SavedTab({
    required this.url,
    required this.title,
    this.group,
    this.lastUsed,
  });

  final String url;
  final String title;
  final String? group;
  final DateTime? lastUsed;

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'title': title,
    if (group != null) 'group': group,
    if (lastUsed != null) 'lastUsed': lastUsed!.millisecondsSinceEpoch,
  };

  static SavedTab fromJson(Map<Object?, Object?> j) => SavedTab(
    url: j['url'] as String? ?? '',
    title: j['title'] as String? ?? '',
    group: j['group'] as String?,
    lastUsed: j['lastUsed'] is int
        ? DateTime.fromMillisecondsSinceEpoch(j['lastUsed']! as int)
        : null,
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
  final List<SavedTab> tabs;
  final DateTime updatedAt;

  String get id => 'tabs-$deviceId';

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'deviceName': deviceName,
    'tabs': <Map<String, Object?>>[for (final SavedTab t in tabs) t.toJson()],
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static DeviceTabs fromJson(String id, Map<String, Object?> j, DateTime at) =>
      DeviceTabs(
        deviceId: j['deviceId'] as String? ?? id,
        deviceName: j['deviceName'] as String? ?? 'Another device',
        tabs: <SavedTab>[
          for (final Object? t in (j['tabs'] as List<Object?>? ?? const []))
            if (t is Map) SavedTab.fromJson(t),
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

/// A site permission ZT Browser asks about: camera, microphone, location.
abstract final class SitePermission {
  static const String camera = 'camera';
  static const String microphone = 'microphone';
  static const String location = 'location';

  static String label(String kind) => switch (kind) {
    camera => 'Camera',
    microphone => 'Microphone',
    location => 'Location',
    _ => kind,
  };
}

/// Browser settings, synced so every device behaves the same.
class BrowserSettings {
  const BrowserSettings({
    this.searchEngine = 'duckduckgo',
    this.blockTrackers = true,
    this.httpsOnly = true,
    this.allowedSites = const <String>[],
    this.historyDays = 90,
    this.hideElements = true,
    this.fingerprinting = true,
    this.javascriptOff = const <String>[],
    this.textZoom = 100,
    this.darkPages = true,
    this.closeTabsAfterDays,
    this.sitePermissions = const <String, Map<String, bool>>{},
    this.autofillTipDismissed = false,
  });

  static const String itemId = 'browser-settings';

  final String searchEngine;
  final bool blockTrackers;
  final bool httpsOnly;

  /// Sites (like `example.com`) where the user turned protection off.
  final List<String> allowedSites;

  /// How long history is kept: 0 keeps none, null keeps it forever.
  final int? historyDays;

  /// Hide cookie banners and the empty boxes blocked ads leave.
  final bool hideElements;

  /// Add noise to what sites can read to tell your phone apart.
  final bool fingerprinting;

  /// Sites (like `example.com`) where JavaScript is off.
  final List<String> javascriptOff;

  /// Page text size in percent.
  final int textZoom;

  /// Darken pages without a dark design when the phone is in dark mode.
  final bool darkPages;

  /// Close tabs not looked at for this many days; null never.
  final int? closeTabsAfterDays;

  /// Remembered answers per host: {"meet.example.com": {"camera": true}}.
  final Map<String, Map<String, bool>> sitePermissions;

  /// The password manager tip on the start page was dismissed.
  final bool autofillTipDismissed;

  static const List<int?> historyChoices = <int?>[0, 7, 30, 90, 365, null];
  static const List<int?> closeTabsChoices = <int?>[null, 1, 7, 14, 30];
  static const List<int> textZoomChoices = <int>[
    80,
    90,
    100,
    115,
    130,
    150,
    175,
    200,
  ];

  static String historyLabel(int? days) => switch (days) {
    0 => "Don't keep history",
    null => 'Forever',
    7 => '1 week',
    30 => '1 month',
    90 => '3 months',
    365 => '1 year',
    final int d => '$d days',
  };

  static String closeTabsLabel(int? days) => switch (days) {
    null => 'Never',
    1 => 'After a day',
    7 => 'After a week',
    14 => 'After 2 weeks',
    30 => 'After a month',
    final int d => 'After $d days',
  };

  SearchEngine get engine => SearchEngine.byId(searchEngine);

  /// The remembered answer for [kind] on [host], or null to ask.
  bool? permissionFor(String host, String kind) =>
      sitePermissions[host.toLowerCase()]?[kind];

  BrowserSettings withPermission(String host, String kind, bool? allow) {
    final String h = host.toLowerCase();
    final Map<String, Map<String, bool>> all = <String, Map<String, bool>>{
      for (final MapEntry<String, Map<String, bool>> e
          in sitePermissions.entries)
        e.key: <String, bool>{...e.value},
    };
    final Map<String, bool> site = all.putIfAbsent(h, () => <String, bool>{});
    if (allow == null) {
      site.remove(kind);
    } else {
      site[kind] = allow;
    }
    if (site.isEmpty) all.remove(h);
    return copyWith(sitePermissions: all);
  }

  BrowserSettings copyWith({
    String? searchEngine,
    bool? blockTrackers,
    bool? httpsOnly,
    List<String>? allowedSites,
    int? Function()? historyDays,
    bool? hideElements,
    bool? fingerprinting,
    List<String>? javascriptOff,
    int? textZoom,
    bool? darkPages,
    int? Function()? closeTabsAfterDays,
    Map<String, Map<String, bool>>? sitePermissions,
    bool? autofillTipDismissed,
  }) => BrowserSettings(
    searchEngine: searchEngine ?? this.searchEngine,
    blockTrackers: blockTrackers ?? this.blockTrackers,
    httpsOnly: httpsOnly ?? this.httpsOnly,
    allowedSites: allowedSites ?? this.allowedSites,
    historyDays: historyDays != null ? historyDays() : this.historyDays,
    hideElements: hideElements ?? this.hideElements,
    fingerprinting: fingerprinting ?? this.fingerprinting,
    javascriptOff: javascriptOff ?? this.javascriptOff,
    textZoom: textZoom ?? this.textZoom,
    darkPages: darkPages ?? this.darkPages,
    closeTabsAfterDays: closeTabsAfterDays != null
        ? closeTabsAfterDays()
        : this.closeTabsAfterDays,
    sitePermissions: sitePermissions ?? this.sitePermissions,
    autofillTipDismissed: autofillTipDismissed ?? this.autofillTipDismissed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'searchEngine': searchEngine,
    'blockTrackers': blockTrackers,
    'httpsOnly': httpsOnly,
    'allowedSites': allowedSites,
    // -1 is "forever", so a missing key still means the default.
    'historyDays': historyDays ?? -1,
    'hideElements': hideElements,
    'fingerprinting': fingerprinting,
    'javascriptOff': javascriptOff,
    'textZoom': textZoom,
    'darkPages': darkPages,
    // -1 is "never", the default.
    'closeTabsAfterDays': closeTabsAfterDays ?? -1,
    'sitePermissions': sitePermissions,
    'autofillTipDismissed': autofillTipDismissed,
  };

  static List<String> _strings(Object? v) => <String>[
    for (final Object? s in (v as List<Object?>? ?? const <Object?>[]))
      if (s is String) s,
  ];

  static BrowserSettings fromJson(
    String id,
    Map<String, Object?> j,
    DateTime at,
  ) {
    final Object? days = j['historyDays'];
    final Object? close = j['closeTabsAfterDays'];
    final Object? zoom = j['textZoom'];
    final Map<String, Map<String, bool>> perms = <String, Map<String, bool>>{};
    final Object? rawPerms = j['sitePermissions'];
    if (rawPerms is Map) {
      for (final MapEntry<Object?, Object?> e in rawPerms.entries) {
        final Object? kinds = e.value;
        if (e.key is! String || kinds is! Map) continue;
        final Map<String, bool> site = <String, bool>{
          for (final MapEntry<Object?, Object?> k in kinds.entries)
            if (k.key is String && k.value is bool)
              k.key! as String: k.value! as bool,
        };
        if (site.isNotEmpty) perms[e.key! as String] = site;
      }
    }
    return BrowserSettings(
      searchEngine: j['searchEngine'] as String? ?? 'duckduckgo',
      blockTrackers: j['blockTrackers'] as bool? ?? true,
      httpsOnly: j['httpsOnly'] as bool? ?? true,
      allowedSites: _strings(j['allowedSites']),
      historyDays: days is int ? (days < 0 ? null : days) : 90,
      hideElements: j['hideElements'] as bool? ?? true,
      fingerprinting: j['fingerprinting'] as bool? ?? true,
      javascriptOff: _strings(j['javascriptOff']),
      textZoom: zoom is int && zoom >= 50 && zoom <= 300 ? zoom : 100,
      darkPages: j['darkPages'] as bool? ?? true,
      closeTabsAfterDays: close is int && close > 0 ? close : null,
      sitePermissions: perms,
      autofillTipDismissed: j['autofillTipDismissed'] as bool? ?? false,
    );
  }
}

/// A page saved to read later. With [saved], its text (reader view) is
/// kept as an encrypted attachment, so it opens offline on every device.
class ReadingItem {
  const ReadingItem({
    required this.id,
    required this.url,
    required this.title,
    required this.addedAt,
    this.read = false,
    this.saved,
    this.excerpt,
  });

  final String id;
  final String url;
  final String title;
  final DateTime addedAt;
  final bool read;
  final ZtAttachmentRef? saved;
  final String? excerpt;

  ReadingItem copyWith({bool? read}) => ReadingItem(
    id: id,
    url: url,
    title: title,
    addedAt: addedAt,
    read: read ?? this.read,
    saved: saved,
    excerpt: excerpt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'title': title,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'read': read,
    if (saved != null) 'saved': saved!.toJson(),
    if (excerpt != null) 'excerpt': excerpt,
  };

  static ReadingItem fromJson(String id, Map<String, Object?> j, DateTime at) {
    ZtAttachmentRef? saved;
    final Object? raw = j['saved'];
    if (raw is Map<String, Object?>) {
      try {
        saved = ZtAttachmentRef.fromJson(raw);
      } on Object {
        saved = null;
      }
    }
    return ReadingItem(
      id: id,
      url: j['url'] as String? ?? '',
      title: j['title'] as String? ?? '',
      addedAt: _ms(j['addedAt'], at),
      read: j['read'] as bool? ?? false,
      saved: saved,
      excerpt: j['excerpt'] as String?,
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

  static final ZtCollection<ReadingItem> reading = ZtCollection<ReadingItem>(
    kind: 'reading',
    fromJson: ReadingItem.fromJson,
    toJson: (ReadingItem r) => r.toJson(),
    idOf: (ReadingItem r) => r.id,
  );

  static final ZtCollection<BrowserSettings> settings =
      ZtCollection<BrowserSettings>(
        kind: 'settings',
        fromJson: BrowserSettings.fromJson,
        toJson: (BrowserSettings s) => s.toJson(),
        idOf: (_) => BrowserSettings.itemId,
      );
}
