/// Turns an article's HTML (Readability's cleaned content) into the parts
/// read aloud one after another: paragraphs and headings as plain text,
/// long ones split at sentence ends so no part exceeds [maxLength]
/// (Android's text to speech takes at most about 4000 characters at once,
/// and shorter parts make pause and skip feel immediate).
List<String> speechParts(String html, {String? title, int maxLength = 600}) {
  final List<String> out = <String>[];
  if (title != null && title.trim().isNotEmpty) out.add(_clean(title));
  // Drop what is never read: scripts, styles, figure captions' images.
  String s = html.replaceAll(
    RegExp(
      r'<(script|style|noscript|svg|math)\b[\s\S]*?</\1\s*>',
      caseSensitive: false,
    ),
    ' ',
  );
  // Block ends become paragraph breaks; inline tags just go.
  s = s.replaceAll(
    RegExp(
      r'</?(p|div|section|article|h[1-6]|li|ul|ol|blockquote|pre|tr|table|figure|figcaption|dd|dt|header|footer)\b[^>]*>|<br\s*/?>',
      caseSensitive: false,
    ),
    '\n\n',
  );
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  for (final String block in s.split(RegExp(r'\n\s*\n'))) {
    final String text = _clean(_entities(block));
    if (text.isEmpty) continue;
    out.addAll(_split(text, maxLength));
  }
  return out;
}

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Long text cut at sentence ends (., !, ?, and the Hebrew/Arabic ones),
/// or at spaces if a sentence alone is too long.
List<String> _split(String text, int max) {
  if (text.length <= max) return <String>[text];
  final List<String> sentences = <String>[];
  final RegExp end = RegExp(r'(?<=[.!?؟׃。])\s+');
  sentences.addAll(text.split(end));
  final List<String> out = <String>[];
  final StringBuffer cur = StringBuffer();
  void flush() {
    if (cur.isNotEmpty) out.add(cur.toString().trim());
    cur.clear();
  }

  for (final String sentence in sentences) {
    if (sentence.length > max) {
      flush();
      String rest = sentence;
      while (rest.length > max) {
        int cut = rest.lastIndexOf(' ', max);
        if (cut <= 0) cut = max;
        out.add(rest.substring(0, cut).trim());
        rest = rest.substring(cut).trim();
      }
      if (rest.isNotEmpty) cur.write(rest);
      continue;
    }
    if (cur.length + sentence.length + 1 > max) flush();
    if (cur.isNotEmpty) cur.write(' ');
    cur.write(sentence);
  }
  flush();
  return out.where((String p) => p.isNotEmpty).toList();
}

String _entities(String s) =>
    s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (Match m) {
      final String e = m.group(1)!;
      if (e.startsWith('#x') || e.startsWith('#X')) {
        final int? c = int.tryParse(e.substring(2), radix: 16);
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      if (e.startsWith('#')) {
        final int? c = int.tryParse(e.substring(1));
        return c == null ? m.group(0)! : String.fromCharCode(c);
      }
      return switch (e) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        'ndash' => '–',
        'mdash' => '—',
        'hellip' => '…',
        'rsquo' || 'lsquo' => "'",
        'rdquo' || 'ldquo' => '"',
        _ => m.group(0)!,
      };
    });
