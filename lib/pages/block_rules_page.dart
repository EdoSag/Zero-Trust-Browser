import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/filter_lists.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

final _listStatusProvider =
    FutureProvider.autoDispose<Map<String, FilterListStatus>>(
      (ref) => ref.read(userBlockRulesProvider).statuses(),
    );

/// B30: hosts the user blocks or never blocks, and extra filter lists.
/// The rules sync with the account like every setting; the lists'
/// contents are downloaded on each phone, straight from their address.
class BlockRulesPage extends ConsumerWidget {
  const BlockRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final Map<String, FilterListStatus> status =
        ref.watch(_listStatusProvider).value ??
        const <String, FilterListStatus>{};
    final BrowserData data = ref.read(browserDataProvider);
    final UserBlockRules rules = ref.read(userBlockRulesProvider);
    final MaterialLocalizations ml = MaterialLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    Future<void> save(BrowserSettings next) async {
      await data.saveSettings(next);
      await rules.apply();
    }

    Future<void> addHost({required bool block}) async {
      final String? host = await _askHost(context, block);
      if (host == null) return;
      final BrowserSettings now = ref.read(browserSettingsProvider);
      await save(
        block
            ? now.copyWith(
                blockedHosts: <String>{...now.blockedHosts, host}.toList(),
                unblockedHosts: now.unblockedHosts
                    .where((String h) => h != host)
                    .toList(),
              )
            : now.copyWith(
                unblockedHosts: <String>{...now.unblockedHosts, host}.toList(),
                blockedHosts: now.blockedHosts
                    .where((String h) => h != host)
                    .toList(),
              ),
      );
    }

    Future<void> addList() async {
      final String? url = await _askListUrl(context);
      if (url == null) return;
      final BrowserSettings now = ref.read(browserSettingsProvider);
      if (now.filterLists.contains(url)) return;
      await data.saveSettings(
        now.copyWith(filterLists: <String>[...now.filterLists, url]),
      );
      try {
        final int n = await rules.fetch(url);
        messenger.showSnackBar(
          SnackBar(content: Text(l.filterListAdded(ml.formatDecimal(n)))),
        );
      } on Object {
        messenger.showSnackBar(SnackBar(content: Text(l.filterListFailed)));
      }
      await rules.apply();
      ref.invalidate(_listStatusProvider);
    }

    Widget header(String text) => Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );

    Widget hostTile(String host, {required bool block}) => ListTile(
      leading: Icon(block ? Icons.block : Icons.check_circle_outline),
      title: Text(host, textDirection: TextDirection.ltr),
      trailing: IconButton(
        tooltip: l.remove,
        icon: const Icon(Icons.close),
        onPressed: () {
          final BrowserSettings now = ref.read(browserSettingsProvider);
          save(
            block
                ? now.copyWith(
                    blockedHosts: now.blockedHosts
                        .where((String h) => h != host)
                        .toList(),
                  )
                : now.copyWith(
                    unblockedHosts: now.unblockedHosts
                        .where((String h) => h != host)
                        .toList(),
                  ),
          );
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.blockRules)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l.blockRulesExplain),
          ),
          header(l.alwaysBlock),
          for (final String h in s.blockedHosts) hostTile(h, block: true),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.addHostToBlock),
            onTap: () => addHost(block: true),
          ),
          header(l.neverBlock),
          for (final String h in s.unblockedHosts) hostTile(h, block: false),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l.addHostToAllow),
            onTap: () => addHost(block: false),
          ),
          header(l.extraFilterLists),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l.extraFilterListsExplain,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final String url in s.filterLists)
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: Text(
                url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
              ),
              subtitle: Text(_listLine(context, status[url])),
              onTap: () async {
                final ScaffoldMessengerState m = messenger;
                try {
                  final int n = await rules.fetch(url);
                  m.showSnackBar(
                    SnackBar(
                      content: Text(l.filterListUpdated(ml.formatDecimal(n))),
                    ),
                  );
                } on Object {
                  m.showSnackBar(SnackBar(content: Text(l.filterListFailed)));
                }
                await rules.apply();
                ref.invalidate(_listStatusProvider);
              },
              trailing: IconButton(
                tooltip: l.remove,
                icon: const Icon(Icons.close),
                onPressed: () async {
                  final BrowserSettings now = ref.read(browserSettingsProvider);
                  await save(
                    now.copyWith(
                      filterLists: now.filterLists
                          .where((String u) => u != url)
                          .toList(),
                    ),
                  );
                  ref.invalidate(_listStatusProvider);
                },
              ),
            ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text(l.addFilterList),
            onTap: addList,
          ),
        ],
      ),
    );
  }

  static String _count(BuildContext context, int n) =>
      MaterialLocalizations.of(context).formatDecimal(n);

  static String _listLine(BuildContext context, FilterListStatus? s) {
    final AppL10n l = context.l10n;
    if (s == null || s.fetchedAt == null) {
      return s?.error != null ? l.filterListFailed : l.filterListNotYet;
    }
    final String date = MaterialLocalizations.of(
      context,
    ).formatShortDate(s.fetchedAt!);
    final String line = l.filterListStatus(_count(context, s.hosts), date);
    return s.error == null ? line : '$line · ${l.filterListFailed}';
  }

  static Future<String?> _askHost(BuildContext context, bool block) async {
    final AppL10n l = context.l10n;
    final TextEditingController c = TextEditingController();
    String? error;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext d) => StatefulBuilder(
        builder: (BuildContext d, StateSetter set) {
          void done() {
            final String? h = cleanHostRule(c.text);
            if (h == null) {
              set(() => error = l.notAHost);
              return;
            }
            Navigator.pop(d, h);
          }

          return AlertDialog(
            title: Text(block ? l.addHostToBlock : l.addHostToAllow),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(block ? l.blockHostExplain : l.allowHostExplain),
                const SizedBox(height: 8),
                TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'ads.example.com',
                    errorText: error,
                  ),
                  onSubmitted: (_) => done(),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: done, child: Text(l.save)),
            ],
          );
        },
      ),
    );
    c.dispose();
    return result;
  }

  static Future<String?> _askListUrl(BuildContext context) async {
    final AppL10n l = context.l10n;
    final TextEditingController c = TextEditingController();
    String? error;
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext d) => StatefulBuilder(
        builder: (BuildContext d, StateSetter set) {
          void done() {
            final String? url = webAddress(c.text);
            if (url == null || !url.startsWith('https://')) {
              set(() => error = l.filterListNeedsHttps);
              return;
            }
            Navigator.pop(d, url);
          }

          return AlertDialog(
            title: Text(l.addFilterList),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l.addFilterListExplain),
                const SizedBox(height: 8),
                TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/hosts.txt',
                    errorText: error,
                  ),
                  onSubmitted: (_) => done(),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d),
                child: Text(l.cancel),
              ),
              FilledButton(onPressed: done, child: Text(l.add)),
            ],
          );
        },
      ),
    );
    c.dispose();
    return result;
  }
}
