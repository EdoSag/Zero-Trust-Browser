import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/pages/site_permissions_page.dart';

final _defaultBrowserProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(browserEngineProvider).isDefaultBrowser(),
);

final _blocklistProvider = FutureProvider.autoDispose<Map<Object?, Object?>>(
  (ref) => ref.read(browserEngineProvider).blocklistInfo(),
);

final _autofillProvider = FutureProvider.autoDispose<Map<Object?, Object?>>(
  (ref) => ref.read(browserEngineProvider).autofillStatus(),
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
    final Map<Object?, Object?> list =
        ref.watch(_blocklistProvider).value ?? const <Object?, Object?>{};
    final int listed = (list['size'] as int?) ?? 0;
    final String listDate = (list['date'] as String?) ?? '';
    final Map<Object?, Object?> autofill =
        ref.watch(_autofillProvider).value ?? const <Object?, Object?>{};
    final String? passwordManager = autofill['service'] as String?;

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
        const _Header('Privacy'),
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
          secondary: const Icon(Icons.cookie_outlined),
          title: const Text('Hide cookie banners and ad boxes'),
          subtitle: const Text(
            'Hides "accept cookies" pop-ups (without accepting anything) '
            'and the empty spaces blocked ads leave. EasyList Cookie List.',
          ),
          value: s.hideElements,
          onChanged: s.blockTrackers
              ? (bool v) => save(s.copyWith(hideElements: v))
              : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Fingerprinting protection'),
          subtitle: const Text(
            'Adds noise to what sites read to recognise your phone '
            '(canvas, audio, graphics chip, memory), different on every '
            'site and every time you open the app.',
          ),
          value: s.fingerprinting,
          onChanged: (bool v) => save(s.copyWith(fingerprinting: v)),
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
        ListTile(
          leading: const Icon(Icons.update),
          title: const Text('Blocklist updates'),
          subtitle: Text(
            'Downloaded weekly from ZT Browser\'s releases on GitHub and '
            'checked against its signature. '
            '${listDate.isEmpty ? '' : 'List from ${listDate.substring(0, 10)}. '}'
            'Tap to check now.',
          ),
          onTap: () => _checkBlocklist(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('Site permissions'),
          subtitle: Text(
            s.sitePermissions.isEmpty
                ? 'Sites ask before using your camera, microphone or location'
                : '${s.sitePermissions.length} site'
                      '${s.sitePermissions.length == 1 ? '' : 's'} with a '
                      'remembered answer',
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SitePermissionsPage(),
            ),
          ),
        ),
        if (s.allowedSites.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.remove_moderator_outlined),
            title: const Text('Sites without protection'),
            subtitle: Text(s.allowedSites.join(', ')),
            onTap: () => _editList(
              context,
              s.allowedSites,
              'Trackers and ads are not blocked on these sites.',
              'Protect',
              (List<String> rest) => save(s.copyWith(allowedSites: rest)),
            ),
          ),
        if (s.javascriptOff.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.code_off),
            title: const Text('JavaScript off'),
            subtitle: Text(s.javascriptOff.join(', ')),
            onTap: () => _editList(
              context,
              s.javascriptOff,
              'JavaScript does not run on these sites.',
              'Turn on',
              (List<String> rest) => save(s.copyWith(javascriptOff: rest)),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Password manager'),
          subtitle: Text(
            autofill['supported'] == false
                ? "This phone doesn't support autofill"
                : passwordManager != null
                ? '$passwordManager fills passwords in ZT Browser, in '
                      'private tabs too. ZT Browser never saves passwords.'
                : 'Pick a password manager (Bitwarden, Proton Pass, '
                      '1Password...) in Android settings to fill sign-in '
                      'forms. ZT Browser never saves passwords itself.',
          ),
          onTap: () async {
            await engine.openAutofillSettings();
            ref.invalidate(_autofillProvider);
          },
        ),
        const _Header('Pages'),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('Text size'),
          subtitle: Text('${s.textZoom}%'),
          onTap: () => _pickTextSize(context, s, save),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('Dark pages'),
          subtitle: const Text(
            'When your phone is in dark mode, darken sites that have no '
            'dark design of their own',
          ),
          value: s.darkPages,
          onChanged: (bool v) => save(s.copyWith(darkPages: v)),
        ),
        const _Header('Tabs and history'),
        ListTile(
          leading: const Icon(Icons.tab_unselected),
          title: const Text('Close unused tabs'),
          subtitle: Text(BrowserSettings.closeTabsLabel(s.closeTabsAfterDays)),
          onTap: () => _pickCloseTabs(context, ref, s, save),
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
            'microphone and location only after you say yes to a site. '
            'No usage statistics sent from the web engine.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Open-source credits'),
          subtitle: Text(
            'EasyList, EasyPrivacy and the EasyList Cookie List by The '
            'EasyList authors (easylist.to), used under CC BY-SA 3.0. '
            'Reader view: Mozilla Readability (Apache 2.0). QR scanner: '
            'ZXing (Apache 2.0).',
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

  Future<void> _editList(
    BuildContext context,
    List<String> sites,
    String explain,
    String undoLabel,
    Future<void> Function(List<String>) save,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(explain),
            ),
            for (final String site in sites)
              ListTile(
                title: Text(site),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(sheet);
                    save(sites.where((String x) => x != site).toList());
                  },
                  child: Text(undoLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTextSize(
    BuildContext context,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: const Text('Text size'),
        children: <Widget>[
          RadioGroup<int>(
            groupValue: s.textZoom,
            onChanged: (int? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final int z in BrowserSettings.textZoomChoices)
                  RadioListTile<int>(
                    value: z,
                    title: Text(
                      '$z%',
                      style: TextStyle(fontSize: 16 * z / 100),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await save(s.copyWith(textZoom: picked));
  }

  Future<void> _pickCloseTabs(
    BuildContext context,
    WidgetRef ref,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    const int never = -1;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: const Text('Close unused tabs'),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              "Tabs you haven't looked at for this long close by "
              'themselves. Private tabs always close when the app locks.',
            ),
          ),
          RadioGroup<int>(
            groupValue: s.closeTabsAfterDays ?? never,
            onChanged: (int? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final int? days in BrowserSettings.closeTabsChoices)
                  RadioListTile<int>(
                    value: days ?? never,
                    title: Text(BrowserSettings.closeTabsLabel(days)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked == null) return;
    final int? days = picked == never ? null : picked;
    await save(s.copyWith(closeTabsAfterDays: () => days));
    if (days != null) {
      await ref.read(tabsProvider.notifier).closeUnused(days);
    }
  }

  Future<void> _checkBlocklist(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking for a newer blocklist…')),
    );
    final BlocklistCheck result = await ref
        .read(blocklistUpdaterProvider)
        .checkIfDue(force: true);
    // The engine reads a new list in the background.
    await Future<void>.delayed(const Duration(seconds: 2));
    ref.invalidate(_blocklistProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            BlocklistCheck.updated => 'Blocklist updated',
            BlocklistCheck.upToDate ||
            BlocklistCheck.notDue => 'The blocklist is up to date',
            BlocklistCheck.failed => "Couldn't check now. Try again later.",
          }),
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

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
