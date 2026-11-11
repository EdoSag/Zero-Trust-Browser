import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/privacy_report_page.dart';
import 'package:zerotrust_browser/pages/shortcuts_page.dart';
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
    final AppL10n l = context.l10n;
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
    void push(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return ZtSettingsPage(
      showSyncStatus: true,
      onSignedOut: () =>
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst),
      onOpenUrl: (Uri url) =>
          launchUrl(url, mode: LaunchMode.externalApplication),
      appSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.open_in_browser),
          title: Text(l.defaultBrowser),
          subtitle: Text(isDefault ? l.defaultBrowserOn : l.defaultBrowserOff),
          onTap: isDefault
              ? null
              : () async {
                  await engine.openDefaultBrowserSettings();
                  ref.invalidate(_defaultBrowserProvider);
                },
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: Text(l.searchEngine),
          subtitle: Text(s.engine.name),
          onTap: () => _pickEngine(context, ref),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.manage_search),
          title: Text(l.searchSuggestions),
          subtitle: Text(
            s.engine.suggest == null
                ? l.searchSuggestionsNone(s.engine.name)
                : s.searchSuggestions
                ? l.searchSuggestionsOn(s.engine.name)
                : l.searchSuggestionsOff,
          ),
          value: s.searchSuggestions && s.engine.suggest != null,
          onChanged: s.engine.suggest == null
              ? null
              : (bool v) => _setSuggestions(context, ref, v),
        ),
        _Header(l.privacy),
        SwitchListTile(
          secondary: const Icon(Icons.shield_outlined),
          title: Text(l.blockTrackers),
          subtitle: Text(
            listed > 0
                ? l.blockTrackersCount(
                    MaterialLocalizations.of(context).formatDecimal(listed),
                  )
                : l.blockTrackersNoCount,
          ),
          value: s.blockTrackers,
          onChanged: (bool v) => save(s.copyWith(blockTrackers: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.cookie_outlined),
          title: Text(l.hideBanners),
          subtitle: Text(l.hideBannersSub),
          value: s.hideElements,
          onChanged: s.blockTrackers
              ? (bool v) => save(s.copyWith(hideElements: v))
              : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.link_off),
          title: Text(l.stripTracking),
          subtitle: Text(l.stripTrackingSub),
          value: s.stripTracking,
          onChanged: (bool v) => save(s.copyWith(stripTracking: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: Text(l.fingerprinting),
          subtitle: Text(l.fingerprintingSub),
          value: s.fingerprinting,
          onChanged: (bool v) => save(s.copyWith(fingerprinting: v)),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_outline),
          title: Text(l.httpsOnly),
          subtitle: Text(l.httpsOnlySub),
          value: s.httpsOnly,
          onChanged: (bool v) => save(s.copyWith(httpsOnly: v)),
        ),
        // Tap the row for the report; the switch turns counting on or off.
        ListTile(
          leading: const Icon(Icons.insights_outlined),
          title: Text(l.privacyReport),
          subtitle: Text(l.privacyReportSub),
          onTap: () => push(const PrivacyReportPage()),
          trailing: Switch(
            value: s.privacyReport,
            onChanged: (bool v) => save(s.copyWith(privacyReport: v)),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.update),
          title: Text(l.blocklistUpdates),
          subtitle: Text(
            listDate.length >= 10
                ? l.blocklistUpdatesSubDated(listDate.substring(0, 10))
                : l.blocklistUpdatesSub,
          ),
          onTap: () => _checkBlocklist(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: Text(l.sitePermissions),
          subtitle: Text(
            s.sitePermissions.isEmpty
                ? l.sitePermissionsNone
                : l.sitePermissionsCount(s.sitePermissions.length),
          ),
          onTap: () => push(const SitePermissionsPage()),
        ),
        if (s.allowedSites.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.remove_moderator_outlined),
            title: Text(l.sitesWithoutProtection),
            subtitle: Text(s.allowedSites.join(', ')),
            onTap: () => _editList(
              context,
              s.allowedSites,
              l.sitesWithoutProtectionExplain,
              l.protect,
              (List<String> rest) => save(s.copyWith(allowedSites: rest)),
            ),
          ),
        if (s.javascriptOff.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.code_off),
            title: Text(l.javascriptOff),
            subtitle: Text(s.javascriptOff.join(', ')),
            onTap: () => _editList(
              context,
              s.javascriptOff,
              l.javascriptOffExplain,
              l.turnOn,
              (List<String> rest) => save(s.copyWith(javascriptOff: rest)),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.password),
          title: Text(l.passwordManager),
          subtitle: Text(
            autofill['supported'] == false
                ? l.autofillUnsupported
                : passwordManager != null
                ? l.autofillActive(passwordManager)
                : l.autofillPick,
          ),
          onTap: () async {
            await engine.openAutofillSettings();
            ref.invalidate(_autofillProvider);
          },
        ),
        _Header(l.startPageSection),
        ListTile(
          leading: const Icon(Icons.push_pin_outlined),
          title: Text(l.shortcuts),
          subtitle: s.shortcuts.isEmpty
              ? null
              : Text(
                  <String>[
                    for (final Shortcut sc in s.shortcuts.take(4)) sc.title,
                  ].join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          onTap: () => push(const ShortcutsPage()),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.trending_up),
          title: Text(l.showMostVisited),
          subtitle: Text(l.showMostVisitedSub),
          value: s.showMostVisited,
          // Turning it back on also brings back sites removed from the row.
          onChanged: (bool v) => save(
            s.copyWith(
              showMostVisited: v,
              hiddenTopSites: v ? const <String>[] : null,
            ),
          ),
        ),
        _Header(l.pagesSection),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: Text(l.textSize),
          subtitle: Text('${s.textZoom}%'),
          onTap: () => _pickTextSize(context, s, save),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: Text(l.darkPages),
          subtitle: Text(l.darkPagesSub),
          value: s.darkPages,
          onChanged: (bool v) => save(s.copyWith(darkPages: v)),
        ),
        _Header(l.tabsAndHistory),
        ListTile(
          leading: const Icon(Icons.tab_unselected),
          title: Text(l.closeUnusedTabs),
          subtitle: Text(l.closeTabsLabel(s.closeTabsAfterDays)),
          onTap: () => _pickCloseTabs(context, ref, s, save),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(l.keepHistory),
          subtitle: Text(l.historyLabel(s.historyDays)),
          onTap: () => _pickHistory(context, ref, s, save),
        ),
        ListTile(
          leading: const Icon(Icons.cookie_outlined),
          title: Text(l.clearCookies),
          subtitle: Text(l.clearCookiesSub),
          onTap: () => _clearSiteData(context, engine),
        ),
        ListTile(
          leading: const Icon(Icons.gpp_good_outlined),
          title: Text(l.alwaysOn),
          subtitle: Text(l.alwaysOnSub),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l.credits),
          subtitle: Text(l.creditsSub),
        ),
      ],
    );
  }

  /// Suggestions send what is typed to the search engine: say so before
  /// turning them on.
  Future<void> _setSuggestions(
    BuildContext context,
    WidgetRef ref,
    bool on,
  ) async {
    final AppL10n l = context.l10n;
    final BrowserSettings s = ref.read(browserSettingsProvider);
    if (on) {
      final bool ok =
          await showDialog<bool>(
            context: context,
            builder: (BuildContext d) => AlertDialog(
              title: Text(l.searchSuggestionsAskTitle),
              content: Text(l.searchSuggestionsAskBody(s.engine.name)),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: Text(l.turnOn),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    await ref
        .read(browserDataProvider)
        .saveSettings(
          ref.read(browserSettingsProvider).copyWith(searchSuggestions: on),
        );
  }

  Future<void> _pickEngine(BuildContext context, WidgetRef ref) async {
    final AppL10n l = context.l10n;
    const String add = '+add';
    final String? id = await showDialog<String>(
      context: context,
      builder: (BuildContext d) => Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          final BrowserSettings s = ref.watch(browserSettingsProvider);
          return SimpleDialog(
            title: Text(l.searchEngine),
            children: <Widget>[
              RadioGroup<String>(
                groupValue: s.engine.id,
                onChanged: (String? v) => Navigator.of(d).pop(v),
                child: Column(
                  children: <Widget>[
                    for (final SearchEngine e in s.engines)
                      RadioListTile<String>(
                        value: e.id,
                        title: Text(e.name),
                        subtitle: e.custom
                            ? Text(
                                e.template.replaceAll('{q}', '%s'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                              )
                            : null,
                        secondary: e.custom
                            ? IconButton(
                                tooltip: l.removeEngine(e.name),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(browserDataProvider)
                                    .saveSettings(
                                      s.copyWith(
                                        // Back to the default when the
                                        // engine in use is removed.
                                        searchEngine: s.searchEngine == e.id
                                            ? SearchEngine.duckDuckGo.id
                                            : null,
                                        customEngines: <SearchEngine>[
                                          for (final SearchEngine x
                                              in s.customEngines)
                                            if (x.id != e.id) x,
                                        ],
                                      ),
                                    ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: const Icon(Icons.add),
                title: Text(l.addSearchEngine),
                onTap: () => Navigator.of(d).pop(add),
              ),
            ],
          );
        },
      ),
    );
    if (id == null || !context.mounted) return;
    final BrowserData data = ref.read(browserDataProvider);
    if (id != add) {
      await data.saveSettings(
        ref.read(browserSettingsProvider).copyWith(searchEngine: id),
      );
      return;
    }
    final SearchEngine? made = await showDialog<SearchEngine>(
      context: context,
      builder: (_) => const _EngineDialog(),
    );
    if (made == null) return;
    final BrowserSettings now = ref.read(browserSettingsProvider);
    await data.saveSettings(
      now.copyWith(
        searchEngine: made.id,
        customEngines: <SearchEngine>[...now.customEngines, made],
      ),
    );
  }

  Future<void> _pickHistory(
    BuildContext context,
    WidgetRef ref,
    BrowserSettings s,
    Future<void> Function(BrowserSettings) save,
  ) async {
    final AppL10n l = context.l10n;
    const int forever = -1;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: Text(l.keepHistory),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l.keepHistoryExplain),
          ),
          RadioGroup<int>(
            groupValue: s.historyDays ?? forever,
            onChanged: (int? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final int? days in BrowserSettings.historyChoices)
                  RadioListTile<int>(
                    value: days ?? forever,
                    title: Text(l.historyLabel(days)),
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
    final AppL10n l = context.l10n;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: Text(l.textSize),
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
    final AppL10n l = context.l10n;
    const int never = -1;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext d) => SimpleDialog(
        title: Text(l.closeUnusedTabs),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(l.closeTabsExplain),
          ),
          RadioGroup<int>(
            groupValue: s.closeTabsAfterDays ?? never,
            onChanged: (int? v) => Navigator.of(d).pop(v),
            child: Column(
              children: <Widget>[
                for (final int? days in BrowserSettings.closeTabsChoices)
                  RadioListTile<int>(
                    value: days ?? never,
                    title: Text(l.closeTabsLabel(days)),
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
    final AppL10n l = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l.checkingBlocklist)));
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
            BlocklistCheck.updated => l.blocklistUpdated,
            BlocklistCheck.upToDate ||
            BlocklistCheck.notDue => l.blocklistUpToDate,
            BlocklistCheck.failed => l.blocklistFailed,
          }),
        ),
      );
  }

  Future<void> _clearSiteData(
    BuildContext context,
    BrowserEngine engine,
  ) async {
    final AppL10n l = context.l10n;
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: Text(l.clearCookiesTitle),
            content: Text(l.clearCookiesBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(l.clear),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await engine.clearBrowsingData();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.cookiesCleared)));
    }
  }
}

/// Name and search address of a search engine to add.
class _EngineDialog extends StatefulWidget {
  const _EngineDialog();

  @override
  State<_EngineDialog> createState() => _EngineDialogState();
}

class _EngineDialogState extends State<_EngineDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _address = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  void _done() {
    final SearchEngine? e = SearchEngine.fromUser(_name.text, _address.text);
    if (e == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return AlertDialog(
      title: Text(l.addSearchEngine),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.name),
            ),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l.engineAddress,
                hintText: 'https://example.com/search?q=%s',
                errorText: _invalid ? l.engineInvalid : null,
                errorMaxLines: 2,
              ),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onSubmitted: (_) => _done(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _done, child: Text(l.add)),
      ],
    );
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
