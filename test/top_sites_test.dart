import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/top_sites.dart';
import 'package:zerotrust_browser/data/models.dart';

HistoryEntry h(String url, int visits) => HistoryEntry(
  id: url,
  url: url,
  title: url,
  lastVisit: DateTime(2026, 11, 10),
  visits: visits,
);

void main() {
  final List<HistoryEntry> history = <HistoryEntry>[
    h('https://news.example/story/1', 3),
    h('https://www.news.example/', 2),
    h('https://shop.example/item?id=4', 6),
    h('https://once.example/', 1),
    h('https://duckduckgo.com/?q=cats', 40),
    h('https://pinned.example/', 9),
    h('https://hidden.example/', 9),
    h('about:blank', 50),
  ];

  test('one entry per site, most visited first, front page preferred', () {
    final List<TopSite> top = topSites(history);
    expect(top.map((TopSite t) => t.host), <String>[
      'hidden.example',
      'pinned.example',
      'shop.example',
      'news.example',
    ]);
    final TopSite news = top.last;
    expect(news.visits, 5);
    expect(news.url, 'https://www.news.example/');
    expect(top[2].url, 'https://shop.example/item?id=4');
  });

  test('pinned and removed sites are left out', () {
    final List<TopSite> top = topSites(
      history,
      pinned: <String>['https://pinned.example/'],
      hidden: <String>['hidden.example'],
      limit: 1,
    );
    expect(top.single.host, 'shop.example');
  });

  test('shortcuts: pin once, unpin, survive a round trip', () {
    BrowserSettings s = const BrowserSettings()
        .withShortcut('https://a.example/', 'A')
        .withShortcut('http://a.example', 'again')
        .withShortcut('https://b.example/x', 'B');
    expect(s.shortcuts.map((Shortcut c) => c.title), <String>['A', 'B']);
    expect(s.isPinned('https://a.example'), isTrue);
    final BrowserSettings back = BrowserSettings.fromJson(
      BrowserSettings.itemId,
      s.copyWith(hiddenTopSites: <String>['x.example']).toJson(),
      DateTime(2026),
    );
    expect(back.shortcuts.last.url, 'https://b.example/x');
    expect(back.hiddenTopSites, <String>['x.example']);
    s = s.withoutShortcut('https://a.example/');
    expect(s.shortcuts.single.title, 'B');
  });

  test('a typed shortcut address', () {
    expect(webAddress('example.com'), 'https://example.com');
    expect(webAddress(' http://example.com/a '), 'http://example.com/a');
    expect(webAddress('two words'), isNull);
    expect(webAddress('nodot'), isNull);
    expect(webAddress(''), isNull);
  });
}
