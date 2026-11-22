import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/widget_links.dart';
import 'package:zerotrust_browser/data/models.dart';

/// W13: the quick links widget shows what the start page shows.
void main() {
  List<Map<String, Object?>> parse(String json) =>
      (jsonDecode(json) as List<Object?>).cast<Map<String, Object?>>();

  Bookmark bookmark(int i, {String? url, String title = ''}) => Bookmark(
    id: 'b$i',
    url: url ?? 'https://site$i.example/',
    title: title.isEmpty ? 'Site $i' : title,
    createdAt: DateTime(2026),
  );

  test('pinned sites first; bookmarks only when nothing is pinned', () {
    final List<Bookmark> bookmarks = <Bookmark>[bookmark(1), bookmark(2)];
    expect(
      parse(
        widgetLinksJson(const <Shortcut>[
          Shortcut(url: 'https://news.example/', title: 'News'),
        ], bookmarks),
      ),
      <Map<String, Object?>>[
        <String, Object?>{'title': 'News', 'url': 'https://news.example/'},
      ],
    );
    expect(
      parse(
        widgetLinksJson(const <Shortcut>[], bookmarks),
      ).map((Map<String, Object?> m) => m['title']),
      <String>['Site 1', 'Site 2'],
    );
  });

  test('at most 12, web addresses only, a name for every link', () {
    final List<Bookmark> many = <Bookmark>[
      Bookmark(
        id: 'js',
        url: 'javascript:alert(1)',
        title: 'Bookmarklet',
        createdAt: DateTime(2026),
      ),
      for (int i = 0; i < 20; i++) bookmark(i),
    ];
    final List<Map<String, Object?>> links = parse(
      widgetLinksJson(const <Shortcut>[], many),
    );
    expect(links, hasLength(widgetLinksMax));
    expect(links.first['title'], 'Site 0');
    expect(
      parse(
        widgetLinksJson(const <Shortcut>[
          Shortcut(url: 'https://www.wikipedia.org/', title: '  '),
        ], const <Bookmark>[]),
      ).single['title'],
      'wikipedia.org',
    );
  });

  test('nothing pinned or bookmarked: an empty list', () {
    expect(widgetLinksJson(const <Shortcut>[], const <Bookmark>[]), '[]');
  });
}
