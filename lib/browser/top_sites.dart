import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/models.dart';

/// A site for the start page's "Most visited" row.
class TopSite {
  const TopSite({required this.host, required this.url, required this.visits});

  /// Without `www.`.
  final String host;

  /// The site's front page when it was visited, else its most visited page.
  final String url;
  final int visits;
}

/// The sites visited most, one per host, most visits first. Search result
/// pages, pinned sites ([pinned], by address) and sites the user removed
/// ([hidden], by host) are left out; so are sites seen only once.
List<TopSite> topSites(
  List<HistoryEntry> history, {
  Iterable<String> pinned = const <String>[],
  Iterable<String> hidden = const <String>[],
  List<SearchEngine> engines = SearchEngine.all,
  int limit = 8,
}) {
  final Set<String> skip = <String>{
    for (final String u in pinned) hostOf(u),
    ...hidden,
  };
  final Set<String> searchHosts = <String>{
    for (final SearchEngine e in engines) hostOf(e.template),
  };
  final Map<String, int> visits = <String, int>{};
  final Map<String, HistoryEntry> best = <String, HistoryEntry>{};
  final Map<String, String> front = <String, String>{};
  for (final HistoryEntry h in history) {
    final Uri? u = Uri.tryParse(h.url);
    if (u == null || (u.scheme != 'https' && u.scheme != 'http')) continue;
    final String host = hostOf(h.url);
    if (host.isEmpty || skip.contains(host) || searchHosts.contains(host)) {
      continue;
    }
    visits[host] = (visits[host] ?? 0) + h.visits;
    final HistoryEntry? b = best[host];
    if (b == null || h.visits > b.visits) best[host] = h;
    if ((u.path.isEmpty || u.path == '/') && !u.hasQuery) front[host] = h.url;
  }
  final List<TopSite> out =
      <TopSite>[
        for (final MapEntry<String, int> e in visits.entries)
          if (e.value >= 2)
            TopSite(
              host: e.key,
              url: front[e.key] ?? best[e.key]!.url,
              visits: e.value,
            ),
      ]..sort((TopSite a, TopSite b) {
        final int byVisits = b.visits.compareTo(a.visits);
        return byVisits != 0 ? byVisits : a.host.compareTo(b.host);
      });
  return out.length > limit ? out.sublist(0, limit) : out;
}
