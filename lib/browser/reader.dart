import 'dart:convert';

/// An article Mozilla Readability found in a page.
class Article {
  const Article({
    required this.title,
    required this.content,
    this.byline,
    this.siteName,
    this.excerpt,
    this.lang,
    this.dir,
  });

  final String title;

  /// Readability's cleaned HTML of the article body.
  final String content;
  final String? byline;
  final String? siteName;
  final String? excerpt;
  final String? lang;
  final String? dir;

  static Article? fromJson(Map<String, Object?>? j) {
    if (j == null) return null;
    final String? content = j['content'] as String?;
    if (content == null || content.trim().isEmpty) return null;
    return Article(
      title: (j['title'] as String?)?.trim() ?? '',
      content: content,
      byline: (j['byline'] as String?)?.trim(),
      siteName: (j['siteName'] as String?)?.trim(),
      excerpt: (j['excerpt'] as String?)?.trim(),
      lang: j['lang'] as String?,
      dir: j['dir'] as String?,
    );
  }
}

const HtmlEscape _escape = HtmlEscape();
const HtmlEscape _attr = HtmlEscape(HtmlEscapeMode.attribute);

/// The reader view page: the article in a calm, readable layout that
/// follows the phone's light or dark mode. Scripts are blocked by its
/// content security policy, so only text, pictures and links remain.
String readerHtml(
  Article a, {
  required String url,
  bool saved = false,
  String savedLabel = 'Saved copy',
}) {
  final String lang = _safeAttr(a.lang, 'en');
  final String dir = a.dir == 'rtl' ? 'rtl' : 'auto';
  final String host = Uri.tryParse(url)?.host ?? '';
  final List<String> meta = <String>[
    if (a.siteName != null && a.siteName!.isNotEmpty) a.siteName!,
    if (a.byline != null && a.byline!.isNotEmpty) a.byline!,
  ];
  return '''<!doctype html>
<html lang="$lang" dir="$dir">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; media-src https:; style-src 'unsafe-inline'">
<title>${_escape.convert(a.title)}</title>
<style>
:root { color-scheme: light dark; --fg: #1c1917; --muted: #57534e; --bg: #fafaf9; --link: #c2410c; }
@media (prefers-color-scheme: dark) { :root { --fg: #e7e5e4; --muted: #a8a29e; --bg: #1c1917; --link: #fb923c; } }
html { background: var(--bg); color: var(--fg); }
body { margin: 0 auto; max-width: 42rem; padding: 1.25rem 1.1rem 4rem;
  font: 1.15rem/1.65 Georgia, "Noto Serif", "Noto Serif Hebrew", serif; overflow-wrap: break-word; }
h1 { font: 700 1.6rem/1.25 system-ui, sans-serif; margin: .5rem 0 .4rem; }
.meta { color: var(--muted); font: .9rem/1.4 system-ui, sans-serif; margin-bottom: 1.5rem; }
.meta a { color: var(--muted); }
.saved { font: .8rem/1.4 system-ui, sans-serif; color: var(--muted); border: 1px solid currentColor;
  border-radius: 1rem; padding: .1rem .6rem; display: inline-block; margin-bottom: .6rem; }
a { color: var(--link); }
img, video, figure, table { max-width: 100%; height: auto; }
figure { margin: 1.2rem 0; } figcaption { color: var(--muted); font-size: .9rem; }
pre, code { font-size: .9rem; white-space: pre-wrap; }
blockquote { margin: 1rem 0; padding-left: 1rem; border-left: 3px solid var(--muted); color: var(--muted); }
</style>
</head>
<body>
${saved ? '<div class="saved" dir="auto">${_escape.convert(savedLabel)}</div>' : ''}
<h1 dir="auto">${_escape.convert(a.title)}</h1>
<div class="meta" dir="auto">${_escape.convert(meta.join(' · '))}${meta.isEmpty ? '' : ' · '}<a href="${_attr.convert(url)}">${_escape.convert(host)}</a></div>
<article dir="auto">
${a.content}
</article>
</body>
</html>''';
}

/// A language tag like `en` or `he-IL`, or [fallback].
String _safeAttr(String? v, String fallback) =>
    (v != null && RegExp(r'^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$').hasMatch(v))
    ? v
    : fallback;
