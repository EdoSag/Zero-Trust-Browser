import 'package:zerotrust_browser/data/models.dart';

/// What the address bar does with typed text: open it as an address when
/// it looks like one, otherwise search for it.
///
/// Typed addresses without a scheme get `https://`. Plain `http://` is only
/// used when typed out, and HTTPS-only mode may still upgrade it.
String addressOrSearch(String input, SearchEngine engine) {
  final String text = input.trim();
  if (text.isEmpty) return engine.home;
  final String lower = text.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('about:')) {
    return text;
  }
  if (!text.contains(' ') && _looksLikeHost(text)) return 'https://$text';
  return engine.searchUrl(text).toString();
}

final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$');
final RegExp _host = RegExp(
  r'^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9](:\d+)?([/?#].*)?$',
  caseSensitive: false,
);

bool _looksLikeHost(String s) =>
    s.startsWith('localhost') || _ipv4.hasMatch(s) || _host.hasMatch(s);

/// The address shown in the bar when not editing: host and path, without
/// `https://` and `www.`. Search result pages show the search words.
String displayAddress(String? url) {
  if (url == null || url.isEmpty) return '';
  final Uri? u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  for (final SearchEngine e in SearchEngine.all) {
    final Uri t = Uri.parse(e.template);
    if (u.host == t.host && u.path == t.path) {
      final String? q = u.queryParameters['q'];
      if (q != null && q.isNotEmpty) return q;
    }
  }
  String host = u.host;
  if (host.startsWith('www.')) host = host.substring(4);
  final String rest = u.path == '/' ? '' : u.path;
  return '$host$rest';
}

/// The host of [url], without `www.`.
String hostOf(String? url) {
  final String h = Uri.tryParse(url ?? '')?.host ?? '';
  return h.startsWith('www.') ? h.substring(4) : h;
}
