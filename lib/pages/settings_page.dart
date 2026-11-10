import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

final _defaultBrowserProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(browserEngineProvider).isDefaultBrowser(),
);

final _blocklistSizeProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.read(browserEngineProvider).blocklistSize(),
);

/// The shared Zero-Trust settings screen, with the browser's own rows.
class BrowserSettingsPage extends ConsumerWidget {
  const BrowserSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final BrowserData data = ref.read(browserDataProvider);
    final BrowserEngine engine = ref.read(browserEngineProvider);
    final bool isDefault = ref.watch(_defaultBrowserProvider).value ?? false;
    final int listed = ref.watch(_blocklistSizeProvider).value ?? 0;

    Future<void> save(BrowserSettings next) => data.saveSettings(next);

    return ZtSettingsPage(
      showSyncStatus: true,
      onSignedOut: () =>
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst),
      onOpenUrl: (Uri url) =>
          launchUrl(url, mode: LaunchMode.externalApplication),
      appSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.open_in_browser),
          title: const Text('Default browser'),
          subtitle: Text(
            isDefault
                ? 'Links from other apps open in ZT Browser'
                : 'Tap to open links from other apps in ZT Browser',
          ),
          onTap: isDefault
              ? null
              : () async {
                  await engine.openDefaultBrowserSettings();
                  ref.invalidate(_defaultBrowserProvider);
                },
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Search engine'),
          subtitle: Text(s.engine.name),
          onTap: () => _pickEngine(context, s, save),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.shield_outlined),
          title: const Text('Block trackers and ads'),
          subtitle: Text(
            listed > 0
                ? '${_thousands(listed)} known tracker and ad hosts, from '
                      'EasyList and EasyPrivacy'
                : 'Known tracker and ad hosts, from EasyList and EasyPrivacy',
          ),
          value: s.blockTrackers,
          onChanged: (bool v) => save(s.copyWith(blockTrackers: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: const Text('HTTPS-only'),
          subtitle: const Text(
            'Open sites securely, and ask before loading one that '
            'only works without encryption',
          ),
          value: s.httpsOnly,
          onChanged: (bool v) => save(s.copyWith(httpsOnly: v)),
        ),
        if (s.allowedSites.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.remove_moderator_outlined),
            title: const Text('Sites without protection'),
            subtitle: Text(s.allowedSites.join(', ')),
            onTap: () => _editAllowed(context, s, save),
          ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Keep history'),
          subtitle: Text(BrowserSettings.historyLabel(s.historyDays)),
          onTap: () => _pickHistory(context, ref, s, save),
        ),
        ListTile(
          leading: const Icon(Icons.cookie_outlined),
          title: const Text('Clear cookies and site data'),
          subtitle: const Text('Signs you out of websites on this phone'),
          onTap: () => _clearSiteData(context, engine),
        ),
        const ListTile(
          leading: Icon(Icons.gpp_good_outlined),
          title: Text('Always on'),
          subtitle: Text(
            'Third-party cookies blocked. Global Privacy Control sent, '
            'telling sites not to sell or share your data. Camera, '
            'microphone and location requests from sites refused. '
            'No usage statistics sent from the web engine.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Blocklists'),
          subtitle: Text(
            'EasyList and EasyPrivacy by The EasyList authors '
            '(easylist.to), used under CC BY-SA 3.0.',
          ),
        ),
      ],
    );
  }

  static String _thousands(int n) => n >= 1000
      ? '${(n / 1000).toStringAsFixed(0)},${(n % 1000).toString().padLeft(3, '0')}'
      : '$n';

  Future<void> _pickEngine(
    BuildContext context,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    final String? id = await showDialog<String>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: const Text('Search engine'),
        children: <Widget>[
          RadioGroup<String>(
            groupValue: s.searchEngine,
            onChanged: (String? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final SearchEngine e in SearchEngine.all)
                  RadioListTile<String>(value: e.id, title: Text(e.name)),
              ],
            ),
          ),
        ],
      ),
    );
    if (id != null) await save(s.copyWith(searchEngine: id));
  }

  Future<void> _pickHistory(
    BuildContext context,
    WidgetRef ref,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    const int forever = -1;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: const Text('Keep history'),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Older pages are deleted from your history on all your '
              'devices.',
            ),
          ),
          RadioGroup<int>(
            groupValue: s.historyDays ?? forever,
            onChanged: (int? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final int? days in BrowserSettings.historyChoices)
                  RadioListTile<int>(
                    value: days ?? forever,
                    title: Text(BrowserSettings.historyLabel(days)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await save(
      s.copyWith(historyDays: () => picked == forever ? null : picked),
    );
    await ref.read(browserDataProvider).pruneHistory();
  }

  Future<void> _editAllowed(
    BuildContext context,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Trackers and ads are not blocked on these sites.'),
            ),
            for (final String site in s.allowedSites)
              ListTile(
                title: Text(site),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(sheet);
                    save(
                      s.copyWith(
                        allowedSites: s.allowedSites
                            .where((String x) => x != site)
                            .toList(),
                      ),
                    );
                  },
                  child: const Text('Protect'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearSiteData(
    BuildContext context,
    BrowserEngine engine,
  ) async {
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: const Text('Clear cookies and site data?'),
            content: const Text(
              'You will be signed out of websites on this phone. Bookmarks '
              'and history stay.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await engine.clearBrowsingData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cookies and site data cleared')),
      );
    }
  }
}
