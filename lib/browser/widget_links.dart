import 'dart:convert';

import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/models.dart';

/// How many links the quick links widget shows (as many as the start page).
const int widgetLinksMax = 12;

/// W13: what the home screen quick links widget shows, as JSON
/// `[{"title", "url"}]`: the start page's pinned sites, or, until something
/// is pinned, the first bookmarks (the start page does the same).
String widgetLinksJson(List<Shortcut> shortcuts, List<Bookmark> bookmarks) {
  final List<(String, String)> links = shortcuts.isNotEmpty
      ? <(String, String)>[for (final Shortcut s in shortcuts) (s.title, s.url)]
      : <(String, String)>[
          for (final Bookmark b in bookmarks) (b.title, b.url),
        ];
  return jsonEncode(<Map<String, String>>[
    for (final (String title, String url)
        in links
            .where(
              ((String, String) l) =>
                  l.$2.startsWith('https://') || l.$2.startsWith('http://'),
            )
            .take(widgetLinksMax))
      <String, String>{
        'title': title.trim().isEmpty ? hostOf(url) : title.trim(),
        'url': url,
      },
  ]);
}
