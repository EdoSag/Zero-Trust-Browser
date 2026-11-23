import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/apply_settings.dart';
import 'package:zerotrust_browser/browser/filter_lists.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/site_permissions_page.dart';

/// The shield in the address bar: is the connection secure, what was
/// blocked on this page (B-7), and protection on or off for this site.
Future<void> showSiteSheet(
  BuildContext context,
  WidgetRef ref,
  BrowserTab tab,
) async {
  final BrowserEngine engine = ref.read(browserEngineProvider);
  final String host = hostOf(tab.url);
  final String site = await engine.siteOf(host);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheet) => Consumer(
      builder: (BuildContext context, WidgetRef ref, _) {
        final AppL10n l = context.l10n;
        final BrowserSettings s = ref.watch(browserSettingsProvider);
        final BrowserTab live =
            ref.watch(tabsProvider.select((TabsState t) => t.current)) ?? tab;
        final bool protectedHere =
            s.blockTrackers && !s.allowedSites.contains(site);
        final TextTheme text = Theme.of(context).textTheme;

        /// Blocking on or off for this whole site, then the page again.
        Future<void> setProtection({required bool on}) async {
          final List<String> allowed = <String>[
            ...s.allowedSites.where((String x) => x != site),
            if (!on) site,
          ];
          final BrowserSettings next = s.copyWith(allowedSites: allowed);
          await ref.read(browserDataProvider).saveSettings(next);
          await applySettings(engine, next);
          await engine.reload(tab.id);
        }

        /// One blocked host allowed on every site (the B30 rules), then
        /// the page again.
        Future<void> allowHost(String blockedHost) async {
          final BrowserSettings now = ref.read(browserSettingsProvider);
          await ref
              .read(browserDataProvider)
              .saveSettings(
                now.copyWith(
                  unblockedHosts: <String>{
                    ...now.unblockedHosts,
                    blockedHost,
                  }.toList(),
                  blockedHosts: now.blockedHosts
                      .where((String h) => h != blockedHost)
                      .toList(),
                ),
              );
          await ref.read(userBlockRulesProvider).apply();
          await engine.reload(tab.id);
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(host, style: text.titleLarge),
                ),
                ListTile(
                  leading: Icon(
                    live.secure
                        ? Icons.lock_outline
                        : Icons.no_encryption_gmailerrorred_outlined,
                  ),
                  title: Text(
                    live.secure ? l.connectionSecure : l.connectionNotSecure,
                  ),
                  subtitle: Text(
                    live.secure
                        ? l.connectionSecureSub
                        : l.connectionNotSecureSub,
                  ),
                ),
                // B-7: one tap from a broken page to a working one.
                if (protectedHere && live.blocked > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: FilledButton.tonalIcon(
                      onPressed: () => setProtection(on: false),
                      icon: const Icon(Icons.build_outlined),
                      label: Text(l.pageBrokenTurnOff),
                    ),
                  ),
                BlockedOnPage(
                  tabId: live.id,
                  count: live.blocked,
                  onAllow: allowHost,
                ),
                if (s.blockTrackers)
                  SwitchListTile(
                    secondary: const Icon(Icons.verified_user_outlined),
                    title: Text(l.protectionOn(site)),
                    subtitle: Text(l.protectionSub),
                    value: protectedHere,
                    onChanged: (bool on) => setProtection(on: on),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(l.trackerBlockingOff),
                    subtitle: Text(l.turnOnInSettings),
                  ),
                if (s.autoClearCookies && !live.private)
                  SwitchListTile(
                    secondary: const Icon(Icons.how_to_reg_outlined),
                    title: Text(l.keepSignedInOn(site)),
                    subtitle: Text(l.keepSignedInSub),
                    value: s.keepsSignedIn(site),
                    onChanged: (bool on) async {
                      await ref
                          .read(browserDataProvider)
                          .saveSettings(
                            s.copyWith(
                              keepSignedIn: <String>[
                                ...s.keepSignedIn.where(
                                  (String x) => x != site,
                                ),
                                if (on) site,
                              ],
                            ),
                          );
                    },
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.code),
                  title: Text(l.javascriptOn(site)),
                  subtitle: Text(l.javascriptSub),
                  value: !s.javascriptOff.contains(site),
                  onChanged: (bool on) async {
                    final BrowserSettings next = s.copyWith(
                      javascriptOff: <String>[
                        ...s.javascriptOff.where((String x) => x != site),
                        if (!on) site,
                      ],
                    );
                    await ref.read(browserDataProvider).saveSettings(next);
                    await applySettings(engine, next);
                    await engine.reload(tab.id);
                  },
                ),
                for (final MapEntry<String, bool> p
                    in (s.sitePermissions[host.toLowerCase()] ??
                            const <String, bool>{})
                        .entries)
                  ListTile(
                    leading: Icon(switch (p.key) {
                      SitePermission.camera => Icons.videocam_outlined,
                      SitePermission.microphone => Icons.mic_none,
                      _ => Icons.location_on_outlined,
                    }),
                    title: Text(l.permissionLabel(p.key)),
                    subtitle: Text(p.value ? l.allowed : l.blocked),
                    onTap: () => editSitePermission(context, ref, host, p.key),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Blocked hosts, most requests first; ties by name.
List<MapEntry<String, int>> sortBlocked(Map<String, int> hosts) =>
    hosts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

/// B-7: "N blocked on this page", opening to the list of what was blocked.
/// A host can be allowed from here when the page needs it.
class BlockedOnPage extends ConsumerWidget {
  const BlockedOnPage({
    super.key,
    required this.tabId,
    required this.count,
    required this.onAllow,
  });

  final String tabId;

  /// Requests blocked so far; the list is read again when it changes.
  final int count;
  final Future<void> Function(String host) onAllow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    if (count == 0) {
      return ListTile(
        leading: const Icon(Icons.shield_outlined),
        title: Text(l.blockedOnPage(0)),
        subtitle: Text(l.blockedOnPageSub),
      );
    }
    return ExpansionTile(
      leading: const Icon(Icons.shield_outlined),
      title: Text(l.blockedOnPage(count)),
      subtitle: Text(l.blockedOnPageTap),
      children: <Widget>[
        FutureBuilder<Map<String, int>>(
          key: ValueKey<int>(count),
          future: ref.read(browserEngineProvider).blockedHosts(tabId),
          builder:
              (BuildContext context, AsyncSnapshot<Map<String, int>> snap) {
                final Map<String, int>? hosts = snap.data;
                if (hosts == null) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (hosts.isEmpty) {
                  return ListTile(title: Text(l.blockedOnPageSub));
                }
                return Column(
                  children: <Widget>[
                    for (final MapEntry<String, int> e in sortBlocked(hosts))
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsetsDirectional.only(
                          start: 72,
                          end: 8,
                        ),
                        title: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                        ),
                        subtitle: Text(l.blockedRequests(e.value)),
                        trailing: TextButton(
                          onPressed: () => onAllow(e.key),
                          child: Text(l.allowHost),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        72,
                        0,
                        16,
                        12,
                      ),
                      child: Text(
                        l.allowHostSub,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
        ),
      ],
    );
  }
}
