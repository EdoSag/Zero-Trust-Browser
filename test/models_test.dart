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
      tabs: <({String url, String title})>[(url: 'https://a.org', title: 'A')],
      updatedAt: at,
    );
    final DeviceTabs back = DeviceTabs.fromJson(d.id, d.toJson(), at);
    expect(back.id, 'tabs-dev1');
    expect(back.tabs.single.url, 'https://a.org');
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
}
