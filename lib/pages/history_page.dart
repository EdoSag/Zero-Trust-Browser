import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/pages/bookmarks_page.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// History, newest first, grouped by day. End-to-end encrypted and synced.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, required this.onOpen});

  final OpenUrl onOpen;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _query = '';

  AppL10n get l => context.l10n;

  static String dayLabel(
    DateTime d,
    DateTime now,
    MaterialLocalizations m,
    AppL10n l,
  ) {
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int ago = today.difference(day).inDays;
    if (ago == 0) return l.today;
    if (ago == 1) return l.yesterday;
    if (ago < 7) return l.daysAgo(ago);
    return m.formatMediumDate(d);
  }

  Future<void> _clear() async {
    final Duration? range = await showDialog<Duration?>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: Text(l.clearHistory),
        children: <Widget>[
          for (final (String label, Duration? span) in <(String, Duration?)>[
            (l.rangeLastHour, const Duration(hours: 1)),
            (l.rangeLast24, const Duration(hours: 24)),
            (l.rangeLast7Days, const Duration(days: 7)),
            (l.rangeAll, const Duration(days: 365 * 100)),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, span),
              child: Text(label),
            ),
        ],
      ),
    );
    if (range == null) return;
    final DateTime since = DateTime.now().subtract(range);
    final List<HistoryEntry> all =
        ref.read(historyProvider).value ?? const <HistoryEntry>[];
    await ref.read(browserDataProvider).deleteHistory(<String>[
      for (final HistoryEntry h in all)
        if (h.lastVisit.isAfter(since)) h.id,
    ]);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.historyCleared)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<HistoryEntry>> all = ref.watch(historyProvider);
    final BrowserSettings settings = ref.watch(browserSettingsProvider);
    final String q = _query.toLowerCase();
    final List<HistoryEntry> shown = (all.value ?? const <HistoryEntry>[])
        .where(
          (HistoryEntry h) =>
              q.isEmpty ||
              h.title.toLowerCase().contains(q) ||
              h.url.toLowerCase().contains(q),
        )
        .toList();
    final DateTime now = DateTime.now();
    final List<Widget> rows = <Widget>[];
    String? lastDay;
    for (final HistoryEntry h in shown) {
      final String day = dayLabel(
        h.lastVisit,
        now,
        MaterialLocalizations.of(context),
        l,
      );
      if (day != lastDay) {
        lastDay = day;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(day, style: Theme.of(context).textTheme.titleSmall),
          ),
        );
      }
      rows.add(
        ListTile(
          leading: SiteIcon(url: h.url),
          title: Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: AddressText(displayAddress(h.url)),
          onTap: () => widget.onOpen(h.url),
          trailing: IconButton(
            tooltip: l.delete,
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(browserDataProvider).deleteHistory(<String>[h.id]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.history),
        actions: <Widget>[
          IconButton(
            tooltip: l.clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: l.searchHistory,
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll<double>(0),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        settings.historyDays == 0
                            ? l.historyOff
                            : q.isEmpty
                            ? l.historyEmpty
                            : l.nothingMatches,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(children: rows),
          ),
        ],
      ),
    );
  }
}
