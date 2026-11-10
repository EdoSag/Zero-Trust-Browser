import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/models.dart';

Stream<List<T>> _watch<T>(Ref ref, ZtCollection<T> c) async* {
  final LocalItemStore store = await ref.watch(ztLocalStoreProvider.future);
  yield* c.watch(store as ZtLocalStore);
}

/// Bookmarks, newest first.
final bookmarksProvider = StreamProvider<List<Bookmark>>((ref) {
  return _watch(ref, BrowserCollections.bookmarks).map(
    (List<Bookmark> l) =>
        l..sort((Bookmark a, Bookmark b) => b.createdAt.compareTo(a.createdAt)),
  );
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

  Future<void> removeBookmark(String id) async {
    final (SyncController sync, _) = await _open();
    await BrowserCollections.bookmarks.delete(sync, id);
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

  Future<void> saveDeviceTabs(List<({String url, String title})> tabs) async {
    final String deviceId = await ref.read(ztDeviceIdProvider.future);
    final (SyncController sync, LocalItemStore store) = await _open();
    final DeviceTabs? old = await BrowserCollections.deviceTabs.get(
      store,
      'tabs-$deviceId',
    );
    if (old != null && _sameTabs(old.tabs, tabs)) return;
    await BrowserCollections.deviceTabs.save(
      sync,
      store,
      DeviceTabs(
        deviceId: deviceId,
        deviceName: old?.deviceName ?? 'Android phone',
        tabs: tabs,
        updatedAt: DateTime.now(),
      ),
    );
  }

  static bool _sameTabs(
    List<({String url, String title})> a,
    List<({String url, String title})> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].url != b[i].url) return false;
    }
    return true;
  }
}

/// The same page for bookmarks: ignores a trailing slash and http vs https.
bool sameAddress(String a, String b) {
  String norm(String u) {
    String s = u.trim();
    if (s.startsWith('http://')) s = 'https://${s.substring(7)}';
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  return norm(a) == norm(b);
}
