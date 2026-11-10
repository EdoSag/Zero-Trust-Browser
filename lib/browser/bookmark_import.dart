import 'package:zerotrust_browser/data/models.dart';

/// Reads bookmarks exported from Chrome, Firefox, Edge, Safari or Brave:
/// the "Netscape bookmark file" HTML they all write.
///
/// Folders become the bookmark's folder name, nested ones joined with
/// " / ". The browsers' own top folders ("Bookmarks bar", "Bookmarks
/// Menu"...) are left out, so their contents land at the top level. Only
/// http and https links are kept.
List<Bookmark> parseBookmarksHtml(String html, {DateTime? now}) {
  final DateTime at = now ?? DateTime.now();
  final List<Bookmark> out = <Bookmark>[];
  final List<String?> folders = <String?>[];
  String? pendingFolder;
  final RegExp token = RegExp(
    r'<\s*(/?)\s*(h3|a|dl)\b([^>]*)>(?:([^<]*)<\s*/\s*(?:h3|a)\s*>)?',
    caseSensitive: false,
  );
  int n = 0;
  for (final RegExpMatch m in token.allMatches(html)) {
    final bool closing = m.group(1) == '/';
    final String tag = m.group(2)!.toLowerCase();
    final String attrs = m.group(3) ?? '';
    final String text = _decode((m.group(4) ?? '').trim());
    switch (tag) {
      case 'h3':
        if (!closing) pendingFolder = _isRootFolder(attrs, text) ? null : text;
      case 'dl':
        if (closing) {
          if (folders.isNotEmpty) folders.removeLast();
        } else {
          folders.add(pendingFolder);
          pendingFolder = null;
        }
      case 'a':
        if (closing) continue;
        final String? href = _attr(attrs, 'href');
        if (href == null) continue;
        final Uri? uri = Uri.tryParse(href);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          continue;
        }
        final String? added = _attr(attrs, 'add_date');
        final int? seconds = added == null ? null : int.tryParse(added);
        final List<String> path = <String>[
          for (final String? f in folders)
            if (f != null && f.isNotEmpty) f,
        ];
        out.add(
          Bookmark(
            id: newItemId(),
            url: href,
            title: text.isEmpty ? href : text,
            // Keep the file's order: newest-first lists show it reversed.
            createdAt: seconds != null && seconds > 0
                ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
                : at.subtract(Duration(milliseconds: n)),
            folder: path.isEmpty ? null : path.join(' / '),
          ),
        );
        n++;
    }
  }
  return out;
}

/// Chrome marks its bar with PERSONAL_TOOLBAR_FOLDER, Firefox its menu and
/// toolbar with UNFILED_BOOKMARKS_FOLDER / names.
bool _isRootFolder(String attrs, String name) {
  final String a = attrs.toLowerCase();
  if (a.contains('personal_toolbar_folder') ||
      a.contains('unfiled_bookmarks_folder')) {
    return true;
  }
  return const <String>{
    'bookmarks bar',
    'bookmarks toolbar',
    'bookmarks menu',
    'other bookmarks',
    'mobile bookmarks',
    'favorites bar',
    'favourites bar',
  }.contains(name.toLowerCase());
}

String? _attr(String attrs, String name) {
  final RegExpMatch? m = RegExp(
    '\\b$name\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(attrs);
  if (m == null) return null;
  return _decode(m.group(2) ?? m.group(3) ?? m.group(4) ?? '');
}

String _decode(String s) => s
    .replaceAllMapped(
      RegExp(r'&#(x?)([0-9a-fA-F]+);'),
      (Match m) => String.fromCharCode(
        int.parse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16),
      ),
    )
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');
