/// Removes tracking from links: tags added to follow a click across sites
/// (`utm_source`, `fbclid`, `gclid`...), redirect wrappers that report the
/// click before sending you on (`google.com/url?q=...`), and AMP copies of
/// pages hosted by Google.
///
/// The same rules run in the web engine for links tapped on a page (see
/// LinkCleaner.kt, which gets [trackingParams], [trackingPrefixes] and
/// [redirectWrappers] from here); this copy cleans links that are copied,
/// shared or typed.
library;

/// Query keys that only identify a click or campaign. Lower case.
///
/// Kept to keys that never change what a page shows: the lists Firefox and
/// Brave strip, plus the common mail and ad platforms. Deliberately not
/// here: `ref`, `source`, `si`, `id` and other words sites use for content.
const Set<String> trackingParams = <String>{
  // Google
  'gclid', 'gclsrc', 'gbraid', 'wbraid', 'dclid', 'gad_source',
  'gad_campaignid', 'srsltid', '_ga', '_gl',
  // Meta
  'fbclid', 'igshid', 'igsh', 'mibextid',
  // Microsoft, X, TikTok, LinkedIn, Pinterest, Snapchat, Reddit, Yandex
  'msclkid', 'twclid', 'ttclid', 'li_fat_id', 'epik', 'sccid', 'sc_cid',
  'rdt_cid', 'yclid', 'ysclid', '_openstat',
  // Mail and marketing platforms
  'mc_cid', 'mc_eid', 'mkt_tok', '_hsenc', '_hsmi', '__hssc', '__hstc',
  '__hsfp', 'hsctatracking', 'oly_anon_id', 'oly_enc_id', 'vero_id',
  'vero_conv', 'ml_subscriber', 'ml_subscriber_hash', 'ck_subscriber_id',
  '_kx', '_ke', 'dm_i', 'wickedid', 'rb_clickid', 's_cid', 'irclickid',
  'iclid', 'mkwid', 'pcrid', 'ef_id', 's_kwcid', 'trk_contact',
  'trk_msg', 'trk_module', 'trk_sid', 'bsft_clkid', 'bsft_uid', '_bta_tid',
  '_bta_c', 'guce_referrer', 'guce_referrer_sig',
};

/// Query keys are also dropped when they start with one of these.
const List<String> trackingPrefixes = <String>['utm_', 'pk_', 'mtm_', 'hsa_'];

/// A page that only passes the click on: on [host] (and its subdomains),
/// under [path], the real address is in the query key [param].
class RedirectWrapper {
  const RedirectWrapper(this.host, this.path, this.param);

  final String host;
  final String path;
  final String param;

  Map<String, String> toJson() => <String, String>{
    'host': host,
    'path': path,
    'param': param,
  };
}

const List<RedirectWrapper> redirectWrappers = <RedirectWrapper>[
  RedirectWrapper('google.com', '/url', 'q'),
  RedirectWrapper('google.com', '/url', 'url'),
  RedirectWrapper('l.facebook.com', '/l.php', 'u'),
  RedirectWrapper('lm.facebook.com', '/l.php', 'u'),
  RedirectWrapper('l.instagram.com', '/', 'u'),
  RedirectWrapper('l.messenger.com', '/l.php', 'u'),
  RedirectWrapper('youtube.com', '/redirect', 'q'),
  RedirectWrapper('out.reddit.com', '/', 'url'),
  RedirectWrapper('duckduckgo.com', '/l/', 'uddg'),
  RedirectWrapper('steamcommunity.com', '/linkfilter/', 'url'),
  RedirectWrapper('away.vk.com', '/away.php', 'to'),
  RedirectWrapper('vk.com', '/away.php', 'to'),
  RedirectWrapper('t.umblr.com', '/redirect', 'z'),
  RedirectWrapper('slack-redir.net', '/link', 'url'),
  RedirectWrapper('linkedin.com', '/redir/redirect', 'url'),
  RedirectWrapper('getpocket.com', '/redirect', 'url'),
];

/// [url] without tracking. Returns [url] itself, untouched, when there is
/// nothing to remove, so clean links are never rewritten.
String cleanUrl(String url) => _clean(url, 0);

String _clean(String url, int depth) {
  final String lower = url.length > 8
      ? url.substring(0, 8).toLowerCase()
      : url.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return url;
  }
  final int hash = url.indexOf('#');
  final String fragment = hash < 0 ? '' : url.substring(hash);
  final String noFragment = hash < 0 ? url : url.substring(0, hash);
  final int mark = noFragment.indexOf('?');
  final String base = mark < 0 ? noFragment : noFragment.substring(0, mark);
  final String query = mark < 0 ? '' : noFragment.substring(mark + 1);

  final int hostStart = base.indexOf('://') + 3;
  final int pathStart = base.indexOf('/', hostStart);
  String host =
      (pathStart < 0
              ? base.substring(hostStart)
              : base.substring(hostStart, pathStart))
          .toLowerCase();
  final int at = host.lastIndexOf('@');
  if (at >= 0) host = host.substring(at + 1);
  final int port = host.indexOf(':');
  if (port >= 0) host = host.substring(0, port);
  if (host.startsWith('www.')) host = host.substring(4);
  final String path = pathStart < 0 ? '/' : base.substring(pathStart);

  if (depth < 3) {
    // AMP copies: the publisher's own page is in the path.
    final String? amp = _ampTarget(host, path);
    if (amp != null) {
      return _clean(
        '$amp${query.isEmpty ? '' : '?$query'}$fragment',
        depth + 1,
      );
    }
    // Redirect wrappers: the real address is in the query.
    if (query.isNotEmpty) {
      for (final RedirectWrapper w in redirectWrappers) {
        if ((host == w.host || host.endsWith('.${w.host}')) &&
            path.startsWith(w.path)) {
          final String? target = _queryValue(query, w.param);
          if (target != null &&
              (target.startsWith('https://') || target.startsWith('http://'))) {
            return _clean(target, depth + 1);
          }
        }
      }
    }
  }

  if (query.isEmpty) return url;
  final List<String> kept = <String>[];
  bool dropped = false;
  for (final String pair in query.split('&')) {
    final int eq = pair.indexOf('=');
    final String key = (eq < 0 ? pair : pair.substring(0, eq)).toLowerCase();
    if (_isTracking(key)) {
      dropped = true;
    } else {
      kept.add(pair);
    }
  }
  if (!dropped) return url;
  return '$base${kept.isEmpty ? '' : '?${kept.join('&')}'}$fragment';
}

bool _isTracking(String key) {
  if (key.isEmpty) return false;
  if (trackingParams.contains(key)) return true;
  for (final String p in trackingPrefixes) {
    if (key.startsWith(p)) return true;
  }
  return false;
}

/// `example-com.cdn.ampproject.org/c/s/example.com/story` and
/// `google.com/amp/s/example.com/story` both hold `example.com/story`.
String? _ampTarget(String host, String path) {
  String? rest;
  if (host.endsWith('.cdn.ampproject.org')) {
    for (final String kind in const <String>['/c/', '/v/']) {
      if (path.startsWith(kind)) rest = path.substring(kind.length);
    }
  } else if ((host == 'google.com' || host.startsWith('google.')) &&
      path.startsWith('/amp/')) {
    rest = path.substring(5);
  }
  if (rest == null) return null;
  final bool secure = rest.startsWith('s/');
  if (secure) rest = rest.substring(2);
  // What follows must start with a host name.
  final int slash = rest.indexOf('/');
  final String targetHost = slash < 0 ? rest : rest.substring(0, slash);
  if (!targetHost.contains('.') ||
      !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(targetHost)) {
    return null;
  }
  return '${secure ? 'https' : 'http'}://$rest';
}

String? _queryValue(String query, String name) {
  for (final String pair in query.split('&')) {
    final int eq = pair.indexOf('=');
    if (eq < 0) continue;
    if (pair.substring(0, eq) == name) {
      try {
        return Uri.decodeQueryComponent(pair.substring(eq + 1));
      } on ArgumentError {
        return null;
      }
    }
  }
  return null;
}
