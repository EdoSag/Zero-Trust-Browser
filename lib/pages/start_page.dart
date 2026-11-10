import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/app/browser_config.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/browser/top_sites.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/shortcuts_page.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// What a new tab shows: a search box, the sites you pinned, the ones you
/// visit most, and for private tabs, what private means.
class StartPage extends ConsumerWidget {
  const StartPage({
    super.key,
    required this.private,
    required this.onOpen,
    required this.onSearch,
    required this.onReport,
  });

  final bool private;
  final ValueChanged<String> onOpen;
  final VoidCallback onSearch;

  /// Opens the privacy report.
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final BrowserData data = ref.read(browserDataProvider);
    final List<Bookmark> bookmarks = private
        ? const <Bookmark>[]
        : ref.watch(bookmarksProvider).value ?? const <Bookmark>[];
    final List<TopSite> top = private || !s.showMostVisited
        ? const <TopSite>[]
        : topSites(
            ref.watch(historyProvider).value ?? const <HistoryEntry>[],
            pinned: <String>[for (final Shortcut sc in s.shortcuts) sc.url],
            hidden: s.hiddenTopSites,
            engines: s.engines,
          );
    final int blockedThisWeek = private || !s.privacyReport
        ? 0
        : ReportSummary.of(
            ref.watch(privacyReportsProvider).value ?? const <PrivacyReport>[],
            now: DateTime.now(),
          ).week;

    Future<void> shortcutMenu(Shortcut sc) async {
      final String? action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.editShortcut),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(l.unpin),
                onTap: () => Navigator.pop(sheet, 'unpin'),
              ),
              ListTile(
                leading: const Icon(Icons.reorder),
                title: Text(l.editShortcuts),
                onTap: () => Navigator.pop(sheet, 'all'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted) return;
      switch (action) {
        case 'edit':
          final Shortcut? made = await askShortcut(context, start: sc);
          if (made == null) return;
          final BrowserSettings now = ref.read(browserSettingsProvider);
          await data.saveSettings(
            now.copyWith(
              shortcuts: <Shortcut>[
                for (final Shortcut x in now.shortcuts)
                  identical(x, sc) || (x.url == sc.url && x.title == sc.title)
                      ? made
                      : x,
              ],
            ),
          );
        case 'unpin':
          await data.saveSettings(
            ref.read(browserSettingsProvider).withoutShortcut(sc.url),
          );
        case 'all':
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ShortcutsPage()),
          );
      }
    }

    Future<void> topSiteMenu(TopSite site) async {
      final String? action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: Text(l.pin),
                onTap: () => Navigator.pop(sheet, 'pin'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(l.dontShowHere),
                onTap: () => Navigator.pop(sheet, 'hide'),
              ),
            ],
          ),
        ),
      );
      final BrowserSettings now = ref.read(browserSettingsProvider);
      switch (action) {
        case 'pin':
          await data.saveSettings(now.withShortcut(site.url, site.host));
        case 'hide':
          await data.saveSettings(
            now.copyWith(
              hiddenTopSites: <String>[...now.hiddenTopSites, site.host],
            ),
          );
      }
    }

    Future<void> addShortcut() async {
      final Shortcut? made = await askShortcut(context);
      if (made == null) return;
      await data.saveSettings(
        ref.read(browserSettingsProvider).withShortcut(made.url, made.title),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      children: <Widget>[
        Center(
          child: private
              ? Icon(
                  Icons.privacy_tip_outlined,
                  size: 56,
                  color: scheme.primary,
                )
              : const ZtBrandMark(app: browserSuiteApp, size: 64),
        ),
        const SizedBox(height: 16),
        Text(
          private ? l.privateTab : 'ZT Browser',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: 24),
        Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onSearch,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.searchWith(s.engine.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (blockedThisWeek > 0) ...<Widget>[
          const SizedBox(height: 12),
          Center(
            child: ActionChip(
              avatar: Icon(Icons.shield_outlined, color: scheme.primary),
              label: Text(l.blockedThisWeek(blockedThisWeek)),
              onPressed: onReport,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (!private && !s.autofillTipDismissed)
          Card(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.password, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(l.yourPasswords, style: text.titleSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(l.passwordsTip, style: text.bodyMedium),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      children: <Widget>[
                        TextButton(
                          onPressed: () => ref
                              .read(browserEngineProvider)
                              .openAutofillSettings(),
                          child: Text(l.chooseInAndroid),
                        ),
                        TextButton(
                          onPressed: () => data.saveSettings(
                            ref
                                .read(browserSettingsProvider)
                                .copyWith(autofillTipDismissed: true),
                          ),
                          child: Text(l.gotIt),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (private)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.privateExplain, style: text.bodyMedium),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(child: Text(l.shortcuts, style: text.titleSmall)),
              if (s.shortcuts.isNotEmpty)
                IconButton(
                  tooltip: l.editShortcuts,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ShortcutsPage(),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 16,
            children: <Widget>[
              for (final Shortcut sc in s.shortcuts)
                _SiteTile(
                  url: sc.url,
                  title: sc.title.isEmpty ? hostOf(sc.url) : sc.title,
                  onTap: () => onOpen(sc.url),
                  onLongPress: () => shortcutMenu(sc),
                ),
              _SiteTile(
                title: l.addShortcut,
                icon: Icons.add,
                onTap: addShortcut,
              ),
            ],
          ),
          if (top.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(l.mostVisited, style: text.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 16,
              children: <Widget>[
                for (final TopSite site in top)
                  _SiteTile(
                    url: site.url,
                    title: site.host,
                    onTap: () => onOpen(site.url),
                    onLongPress: () => topSiteMenu(site),
                  ),
              ],
            ),
          ],
          // Until something is pinned, bookmarks keep their place here.
          if (s.shortcuts.isEmpty && bookmarks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(l.bookmarks, style: text.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 16,
              children: <Widget>[
                for (final Bookmark b in bookmarks.take(12))
                  _SiteTile(
                    url: b.url,
                    title: b.title.isEmpty ? hostOf(b.url) : b.title,
                    onTap: () => onOpen(b.url),
                  ),
              ],
            ),
          ],
          if (s.shortcuts.isEmpty &&
              bookmarks.isEmpty &&
              top.isEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              l.startBlurb,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ],
    );
  }
}

/// A site on the start page: its icon over its name.
class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.title,
    required this.onTap,
    this.url,
    this.icon,
    this.onLongPress,
  });

  final String? url;
  final String title;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 76,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          children: <Widget>[
            if (icon != null)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: scheme.onSurfaceVariant),
              )
            else
              SiteIcon(url: url, size: 44),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
