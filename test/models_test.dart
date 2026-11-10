import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  final DateTime at = DateTime(2026, 11, 9, 12);

  test('bookmark round trip', () {
    final Bookmark b = Bookmark(
      id: newItemId(),
      url: 'https://example.com',
      title: 'Example',
      createdAt: at,
    );
    final Bookmark back = Bookmark.fromJson(b.id, b.toJson(), at);
    expect(back.url, b.url);
    expect(back.title, b.title);
    expect(back.createdAt, at);
    expect(back.folder, isNull);
  });

  test('history entry round trip', () {
    final HistoryEntry h = HistoryEntry(
      id: 'h1',
      url: 'https://a.org',
      title: 'A',
      lastVisit: at,
      visits: 3,
    );
    final HistoryEntry back = HistoryEntry.fromJson('h1', h.toJson(), at);
    expect(back.visits, 3);
    expect(back.lastVisit, at);
  });

  test('settings keep "forever" and defaults', () {
    const BrowserSettings s = BrowserSettings(historyDays: null);
    expect(BrowserSettings.fromJson('x', s.toJson(), at).historyDays, isNull);
    final BrowserSettings empty = BrowserSettings.fromJson('x', const {}, at);
    expect(empty.historyDays, 90);
    expect(empty.blockTrackers, isTrue);
    expect(empty.httpsOnly, isTrue);
    expect(empty.engine.id, 'duckduckgo');
  });

  test('device tabs round trip', () {
    final DeviceTabs d = DeviceTabs(
      deviceId: 'dev1',
      deviceName: 'Pixel',
      tabs: <SavedTab>[
        SavedTab(
          url: 'https://a.org',
          title: 'A',
          group: 'Work',
          lastUsed: DateTime(2026, 11, 1),
        ),
        const SavedTab(url: 'https://b.org', title: 'B'),
      ],
      updatedAt: at,
    );
    final DeviceTabs back = DeviceTabs.fromJson(d.id, d.toJson(), at);
    expect(back.id, 'tabs-dev1');
    expect(back.tabs.first.url, 'https://a.org');
    expect(back.tabs.first.group, 'Work');
    expect(back.tabs.first.lastUsed, DateTime(2026, 11, 1));
    expect(back.tabs.last.group, isNull);
    expect(back.tabs.last.lastUsed, isNull);
  });

  test('each kind lives in its own collection', () {
    final Map<String, Object?> json = BrowserCollections.bookmarks.encode(
      Bookmark(id: 'b', url: 'https://a.org', title: 'A', createdAt: at),
    );
    expect(json[ZtCollection.kindKey], 'bookmark');
    expect(BrowserCollections.history.owns(json), isFalse);
    expect(BrowserCollections.bookmarks.owns(json), isTrue);
  });

  test('item ids are random, never derived from the address', () {
    expect(newItemId(), isNot(newItemId()));
    expect(newItemId(), hasLength(32));
  });

  test('new settings round trip and default sensibly', () {
    final BrowserSettings s = const BrowserSettings(
      hideElements: false,
      fingerprinting: false,
      javascriptOff: <String>['a.org'],
      textZoom: 130,
      darkPages: false,
      closeTabsAfterDays: 7,
      autofillTipDismissed: true,
    ).withPermission('meet.example', SitePermission.camera, true);
    final BrowserSettings back = BrowserSettings.fromJson(
      BrowserSettings.itemId,
      s.toJson(),
      at,
    );
    expect(back.hideElements, isFalse);
    expect(back.fingerprinting, isFalse);
    expect(back.javascriptOff, <String>['a.org']);
    expect(back.textZoom, 130);
    expect(back.darkPages, isFalse);
    expect(back.closeTabsAfterDays, 7);
    expect(back.autofillTipDismissed, isTrue);
    expect(back.permissionFor('meet.example', SitePermission.camera), isTrue);

    // Settings saved by 0.1 (none of the new keys) get the defaults.
    final BrowserSettings old = BrowserSettings.fromJson(
      BrowserSettings.itemId,
      <String, Object?>{'searchEngine': 'brave', 'historyDays': 30},
      at,
    );
    expect(old.hideElements, isTrue);
    expect(old.fingerprinting, isTrue);
    expect(old.textZoom, 100);
    expect(old.closeTabsAfterDays, isNull);
    expect(old.sitePermissions, isEmpty);
  });

  test('a reading list item keeps its encrypted copy reference', () {
    final ZtAttachmentRef ref = ZtAttachmentRef(
      id: '0123456789abcdef0123456789abcdef',
      key: Uint8List.fromList(List<int>.filled(32, 1)),
      size: 42,
      mimeType: 'text/html',
    );
    final ReadingItem r = ReadingItem(
      id: 'r1',
      url: 'https://a.org/story',
      title: 'Story',
      addedAt: at,
      saved: ref,
    );
    final ReadingItem back = ReadingItem.fromJson(
      'r1',
      jsonDecode(jsonEncode(BrowserCollections.reading.encode(r)))
          as Map<String, Object?>,
      at,
    );
    expect(back.saved?.id, ref.id);
    expect(back.saved?.size, 42);
    expect(back.read, isFalse);
    expect(back.copyWith(read: true).saved, isNotNull);
  });
}
