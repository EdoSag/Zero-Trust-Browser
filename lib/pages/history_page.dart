import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/pages/bookmarks_page.dart';
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

  static String dayLabel(DateTime d, DateTime now, MaterialLocalizations l) {
    final DateTime day = DateTime(d.year, d.month, d.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int ago = today.difference(day).inDays;
    if (ago == 0) return 'Today';
    if (ago == 1) return 'Yesterday';
    if (ago < 7) return '$ago days ago';
    return l.formatMediumDate(d);
  }

  Future<void> _clear() async {
    final Duration? range = await showDialog<Duration?>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: const Text('Clear history'),
        children: <Widget>[
          for (final (String label, Duration? span) in <(String, Duration?)>[
            ('Last hour', const Duration(hours: 1)),
            ('Today', const Duration(hours: 24)),
            ('Last 7 days', const Duration(days: 7)),
            ('All history', const Duration(days: 365 * 100)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('History cleared on all your devices')),
      );
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
          subtitle: Text(
            displayAddress(h.url),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onOpen(h.url),
          trailing: IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.close),
            onPressed: () =>
                ref.read(browserDataProvider).deleteHistory(<String>[h.id]),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear history',
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
              hintText: 'Search history',
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
                            ? 'History is off. Turn it on in Settings, under '
                                  'Keep history.'
                            : q.isEmpty
                            ? 'Pages you visit show here, end-to-end '
                                  'encrypted. Private tabs are never saved.'
                            : 'Nothing matches.',
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
