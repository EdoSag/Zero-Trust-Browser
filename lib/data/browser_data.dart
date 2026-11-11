import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

Stream<List<T>> _watch<T>(Ref ref, ZtCollection<T> c) async* {
  final LocalItemStore store = await ref.watch(ztLocalStoreProvider.future);
  yield* c.watch(store as ZtLocalStore);
}

/// Bookmarks in the user's order (dragged ones first, then newest first).
final bookmarksProvider = StreamProvider<List<Bookmark>>((ref) {
  return _watch(
    ref,
    BrowserCollections.bookmarks,
  ).map((List<Bookmark> l) => l..sort(Bookmark.compare));
});

/// History, most recent visit first.
final historyProvider = StreamProvider<List<HistoryEntry>>((ref) {
  return _watch(ref, BrowserCollections.history).map(
    (List<HistoryEntry> l) => l
      ..sort(
        (HistoryEntry a, HistoryEntry b) => b.lastVisit.compareTo(a.lastVisit),
      ),
  );
});

/// Open tabs of the account's other devices, most recently updated first.
final otherDevicesTabsProvider = StreamProvider<List<DeviceTabs>>((ref) async* {
  final String me = await ref.watch(ztDeviceIdProvider.future);
  yield* _watch(ref, BrowserCollections.deviceTabs).map(
    (List<DeviceTabs> all) =>
        all
            .where((DeviceTabs d) => d.deviceId != me && d.tabs.isNotEmpty)
            .toList()
          ..sort(
            (DeviceTabs a, DeviceTabs b) => b.updatedAt.compareTo(a.updatedAt),
          ),
  );
});

/// The account's other devices that run ZT Browser (any that ever saved
/// its open tabs), most recently active first. For "Send to device".
final otherDevicesProvider = StreamProvider<List<DeviceTabs>>((ref) async* {
  final String me = await ref.watch(ztDeviceIdProvider.future);
  yield* _watch(ref, BrowserCollections.deviceTabs).map(
    (List<DeviceTabs> all) =>
        all.where((DeviceTabs d) => d.deviceId != me).toList()..sort(
          (DeviceTabs a, DeviceTabs b) => b.updatedAt.compareTo(a.updatedAt),
        ),
  );
});

/// Pages other devices sent to this one, oldest first.
final sentToMeProvider = StreamProvider<List<SentTab>>((ref) async* {
  final String me = await ref.watch(ztDeviceIdProvider.future);
  yield* _watch(ref, BrowserCollections.sentTabs).map(
    (List<SentTab> all) =>
        all.where((SentTab t) => t.toDevice == me).toList()
          ..sort((SentTab a, SentTab b) => a.sentAt.compareTo(b.sentAt)),
  );
});

/// This phone's name for other devices ("Pixel 8"), from the engine.
final deviceNameProvider = FutureProvider<String>(
  (ref) async => await ref.read(browserEngineProvider).deviceName(),
);

/// The reading list, unread first, then newest.
final readingListProvider = StreamProvider<List<ReadingItem>>((ref) {
  return _watch(ref, BrowserCollections.reading).map(
    (List<ReadingItem> l) => l
      ..sort((ReadingItem a, ReadingItem b) {
        if (a.read != b.read) return a.read ? 1 : -1;
        return b.addedAt.compareTo(a.addedAt);
      }),
  );
});

final _storedSettingsProvider = StreamProvider<List<BrowserSettings>>(
  (ref) => _watch(ref, BrowserCollections.settings),
);

/// The account's browser settings (defaults until changed).
final browserSettingsProvider = Provider<BrowserSettings>((ref) {
  final List<BrowserSettings>? stored = ref
      .watch(_storedSettingsProvider)
      .value;
  return (stored == null || stored.isEmpty)
      ? const BrowserSettings()
      : stored.first;
});

final browserDataProvider = Provider<BrowserData>(BrowserData.new);

/// Writes to the account's encrypted browser data.
class BrowserData {
  BrowserData(this.ref);

  final Ref ref;

  Future<(SyncController, LocalItemStore)> _open() async {
    final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
    return (ref.read(ztSyncControllerProvider.notifier), store);
  }

  // ---- Bookmarks ----------------------------------------------------------

  Bookmark? bookmarkFor(String url) {
    final List<Bookmark> all = ref.read(bookmarksProvider).value ?? const [];
    for (final Bookmark b in all) {
      if (sameAddress(b.url, url)) return b;
    }
    return null;
  }

  Future<void> addBookmark(String url, String title) async {
    if (bookmarkFor(url) != null) return;
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.bookmarks.save(
      sync,
      store,
      Bookmark(
        id: newItemId(),
        url: url,
        title: title.trim().isEmpty ? url : title.trim(),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> saveBookmark(Bookmark b) async {
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.bookmarks.save(sync, store, b);
  }

  /// Adds [items] not bookmarked yet; returns how many were added.
  Future<int> importBookmarks(Iterable<Bookmark> items) async {
    final (SyncController sync, LocalItemStore store) = await _open();
    final List<Bookmark> existing = await BrowserCollections.bookmarks.list(
      store,
    );
    final Set<String> seen = <String>{
      for (final Bookmark b in existing) _norm(b.url),
    };
    int added = 0;
    for (final Bookmark b in items) {
      if (!seen.add(_norm(b.url))) continue;
      await BrowserCollections.bookmarks.save(sync, store, b);
      added++;
    }
    return added;
  }

  Future<void> removeBookmark(String id) async {
    final (SyncController sync, _) = await _open();
    await BrowserCollections.bookmarks.delete(sync, id);
  }

  /// Saves [ordered] (one folder's bookmarks, in the order the user dragged
  /// them into) with positions 0, 1, 2...; only changed ones are written.
  Future<void> reorderBookmarks(List<Bookmark> ordered) async {
    final (SyncController sync, LocalItemStore store) = await _open();
    for (int i = 0; i < ordered.length; i++) {
      final Bookmark b = ordered[i];
      if (b.position == i.toDouble()) continue;
      await BrowserCollections.bookmarks.save(
        sync,
        store,
        b.copyWith(position: i.toDouble()),
      );
    }
  }

  /// Moves a bookmark into [folder] (null: the top level), at its end.
  Future<void> moveBookmark(Bookmark b, String? folder) async {
    final List<Bookmark> all = ref.read(bookmarksProvider).value ?? const [];
    double last = -1;
    for (final Bookmark x in all) {
      if (x.folder == folder && x.position != null && x.position! > last) {
        last = x.position!;
      }
    }
    await saveBookmark(b.copyWith(folder: () => folder, position: last + 1));
  }

  /// Adds an (empty) folder to the list, at its end.
  Future<void> addFolder(String name) async {
    final String n = name.trim();
    if (n.isEmpty) return;
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final List<Bookmark> all = ref.read(bookmarksProvider).value ?? const [];
    final List<String> folders = s.foldersWith(all);
    if (folders.contains(n)) return;
    await saveSettings(s.copyWith(bookmarkFolders: <String>[...folders, n]));
  }

  /// Renames a folder, and moves its bookmarks along.
  Future<void> renameFolder(String from, String to) async {
    final String n = to.trim();
    if (n.isEmpty || n == from) return;
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final List<Bookmark> all = ref.read(bookmarksProvider).value ?? const [];
    await saveSettings(
      s.copyWith(
        bookmarkFolders: <String>[
          for (final String f in s.foldersWith(all))
            if (f == from) n else if (f != n) f,
        ],
      ),
    );
    for (final Bookmark b in all) {
      if (b.folder == from) await saveBookmark(b.copyWith(folder: () => n));
    }
  }

  /// Removes a folder; its bookmarks move to the top level.
  Future<void> deleteFolder(String name) async {
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final List<Bookmark> all = ref.read(bookmarksProvider).value ?? const [];
    await saveSettings(
      s.copyWith(
        bookmarkFolders: <String>[
          for (final String f in s.foldersWith(all))
            if (f != name) f,
        ],
      ),
    );
    for (final Bookmark b in all) {
      if (b.folder == name) await moveBookmark(b, null);
    }
  }

  /// Saves the folders in the order the user dragged them into.
  Future<void> reorderFolders(List<String> ordered) async {
    final BrowserSettings s = ref.read(browserSettingsProvider);
    await saveSettings(s.copyWith(bookmarkFolders: ordered));
  }

  // ---- Send to device -----------------------------------------------------

  /// Sends a page to another of the account's devices: it shows up there
  /// the next time ZT Browser syncs. End-to-end encrypted, like history.
  Future<void> sendTab(DeviceTabs to, String url, String title) async {
    final String me = await ref.read(ztDeviceIdProvider.future);
    final String name = await ref.read(deviceNameProvider.future);
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.sentTabs.save(
      sync,
      store,
      SentTab(
        id: newItemId(),
        url: url,
        title: title.trim().isEmpty ? url : title.trim(),
        fromDevice: me,
        fromName: name,
        toDevice: to.deviceId,
        sentAt: DateTime.now(),
      ),
    );
  }

  /// A received page was opened or dismissed: it's gone everywhere.
  Future<void> dismissSentTab(String id) async {
    final (SyncController sync, _) = await _open();
    await BrowserCollections.sentTabs.delete(sync, id);
  }

  // ---- History ------------------------------------------------------------

  /// Records a visit, unless history is off. Private tabs never call this.
  Future<void> recordVisit(String url, String? title) async {
    final BrowserSettings settings = ref.read(browserSettingsProvider);
    if (settings.historyDays == 0) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return;
    final List<HistoryEntry> all =
        ref.read(historyProvider).value ?? const <HistoryEntry>[];
    HistoryEntry? existing;
    for (final HistoryEntry h in all) {
      if (h.url == url) {
        existing = h;
        break;
      }
    }
    final DateTime now = DateTime.now();
    // A reload or redirect within a minute isn't a new visit.
    if (existing != null &&
        now.difference(existing.lastVisit) < const Duration(minutes: 1) &&
        existing.title == (title ?? existing.title)) {
      return;
    }
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.history.save(
      sync,
      store,
      HistoryEntry(
        id: existing?.id ?? newItemId(),
        url: url,
        title: (title == null || title.trim().isEmpty)
            ? (existing?.title ?? url)
            : title.trim(),
        lastVisit: now,
        visits: (existing?.visits ?? 0) + 1,
      ),
    );
  }

  Future<void> deleteHistory(Iterable<String> ids) async {
    final (SyncController sync, _) = await _open();
    for (final String id in ids) {
      await BrowserCollections.history.delete(sync, id);
    }
  }

  /// Deletes history older than the chosen period ("since" = keep newer).
  Future<void> clearHistory({DateTime? olderThan}) async {
    final (_, LocalItemStore store) = await _open();
    final List<HistoryEntry> all = await BrowserCollections.history.list(store);
    await deleteHistory(<String>[
      for (final HistoryEntry h in all)
        if (olderThan == null || h.lastVisit.isBefore(olderThan)) h.id,
    ]);
  }

  /// Deletes history visited at or after [since] (the fire button).
  Future<void> clearHistorySince(DateTime since) async {
    final (_, LocalItemStore store) = await _open();
    final List<HistoryEntry> all = await BrowserCollections.history.list(store);
    await deleteHistory(<String>[
      for (final HistoryEntry h in all)
        if (!h.lastVisit.isBefore(since)) h.id,
    ]);
  }

  /// Applies the "Keep history" setting.
  Future<void> pruneHistory() async {
    final int? days = ref.read(browserSettingsProvider).historyDays;
    if (days == null) return;
    await clearHistory(
      olderThan: DateTime.now().subtract(Duration(days: days)),
    );
  }

  // ---- Settings and open tabs ---------------------------------------------

  Future<void> saveSettings(BrowserSettings s) async {
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.settings.save(sync, store, s);
  }

  // ---- Reading list -------------------------------------------------------

  ReadingItem? readingFor(String url) {
    final List<ReadingItem> all =
        ref.read(readingListProvider).value ?? const <ReadingItem>[];
    for (final ReadingItem r in all) {
      if (sameAddress(r.url, url)) return r;
    }
    return null;
  }

  /// Adds a page; [html] (its reader view) is kept encrypted for offline.
  Future<void> addToReadingList(
    String url,
    String title, {
    String? html,
    String? excerpt,
  }) async {
    final ReadingItem? old = readingFor(url);
    ZtAttachmentRef? saved;
    if (html != null) {
      final ZtAttachments files = await ref.read(ztAttachmentsProvider.future);
      saved = await files.put(
        Uint8List.fromList(utf8.encode(html)),
        mimeType: 'text/html',
        name: 'page.html',
      );
    }
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.reading.save(
      sync,
      store,
      ReadingItem(
        id: old?.id ?? newItemId(),
        url: url,
        title: title.trim().isEmpty ? url : title.trim(),
        addedAt: DateTime.now(),
        saved: saved ?? old?.saved,
        excerpt: excerpt ?? old?.excerpt,
      ),
    );
    // A new copy replaces the old one.
    if (saved != null && old?.saved != null) {
      final ZtAttachments files = await ref.read(ztAttachmentsProvider.future);
      await files.delete(old!.saved!);
    }
  }

  /// The saved page's HTML, from this phone or downloaded and decrypted.
  Future<String?> readSaved(ReadingItem item) async {
    final ZtAttachmentRef? saved = item.saved;
    if (saved == null) return null;
    final ZtAttachments files = await ref.read(ztAttachmentsProvider.future);
    return utf8.decode(await files.read(saved), allowMalformed: true);
  }

  Future<void> setRead(ReadingItem item, bool read) async {
    final (SyncController sync, LocalItemStore store) = await _open();
    await BrowserCollections.reading.save(
      sync,
      store,
      item.copyWith(read: read),
    );
  }

  Future<void> removeFromReadingList(ReadingItem item) async {
    final (SyncController sync, _) = await _open();
    await BrowserCollections.reading.delete(sync, item.id);
    if (item.saved != null) {
      final ZtAttachments files = await ref.read(ztAttachmentsProvider.future);
      await files.delete(item.saved!);
    }
  }

  Future<void> saveDeviceTabs(List<SavedTab> tabs) async {
    final String deviceId = await ref.read(ztDeviceIdProvider.future);
    final (SyncController sync, LocalItemStore store) = await _open();
    final DeviceTabs? old = await BrowserCollections.deviceTabs.get(
      store,
      'tabs-$deviceId',
    );
    String name = 'Android phone';
    try {
      name = await ref.read(deviceNameProvider.future);
    } on Object {
      name = old?.deviceName ?? name;
    }
    if (old != null && old.deviceName == name && _sameTabs(old.tabs, tabs)) {
      return;
    }
    await BrowserCollections.deviceTabs.save(
      sync,
      store,
      DeviceTabs(
        deviceId: deviceId,
        deviceName: name,
        tabs: tabs,
        updatedAt: DateTime.now(),
      ),
    );
  }

  static bool _sameTabs(List<SavedTab> a, List<SavedTab> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].url != b[i].url || a[i].group != b[i].group) return false;
      // Last use matters to the hour, not to every tap.
      final int? x = a[i].lastUsed?.millisecondsSinceEpoch;
      final int? y = b[i].lastUsed?.millisecondsSinceEpoch;
      if ((x == null) != (y == null)) return false;
      if (x != null && y != null && (x - y).abs() > 3600000) return false;
    }
    return true;
  }

  static String _norm(String u) {
    String s = u.trim();
    if (s.startsWith('http://')) s = 'https://${s.substring(7)}';
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }
}

/// The same page for bookmarks: ignores a trailing slash and http vs https.
bool sameAddress(String a, String b) =>
    BrowserData._norm(a) == BrowserData._norm(b);
