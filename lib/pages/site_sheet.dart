import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/apply_settings.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/pages/site_permissions_page.dart';

/// The shield in the address bar: is the connection secure, how much was
/// blocked, and protection on or off for this site.
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
        final BrowserSettings s = ref.watch(browserSettingsProvider);
        final BrowserTab live =
            ref.watch(tabsProvider.select((TabsState t) => t.current)) ?? tab;
        final bool protectedHere =
            s.blockTrackers && !s.allowedSites.contains(site);
        final TextTheme text = Theme.of(context).textTheme;
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
                    live.secure
                        ? 'Connection is secure'
                        : 'Connection is not secure',
                  ),
                  subtitle: Text(
                    live.secure
                        ? 'What you send and see on this site is encrypted on the way.'
                        : 'Others on your network can see and change this page. '
                              "Don't enter passwords or card numbers here.",
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(
                    live.blocked == 1
                        ? '1 tracker or ad blocked'
                        : '${live.blocked} trackers and ads blocked',
                  ),
                  subtitle: const Text(
                    'On this page, from EasyList and EasyPrivacy.',
                  ),
                ),
                if (s.blockTrackers)
                  SwitchListTile(
                    secondary: const Icon(Icons.verified_user_outlined),
                    title: Text('Protection on $site'),
                    subtitle: const Text(
                      'Turn off only if the site doesn\'t work. It reloads.',
                    ),
                    value: protectedHere,
                    onChanged: (bool on) async {
                      final List<String> allowed = <String>[
                        ...s.allowedSites.where((String x) => x != site),
                        if (!on) site,
                      ];
                      final BrowserSettings next = s.copyWith(
                        allowedSites: allowed,
                      );
                      await ref.read(browserDataProvider).saveSettings(next);
                      await applySettings(engine, next);
                      await engine.reload(tab.id);
                    },
                  )
                else
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Tracker blocking is off'),
                    subtitle: Text('Turn it on in Settings.'),
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.code),
                  title: Text('JavaScript on $site'),
                  subtitle: const Text(
                    'Off makes many sites simpler and harder to track you on, '
                    'but some stop working. It reloads.',
                  ),
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
                    title: Text(SitePermission.label(p.key)),
                    subtitle: Text(p.value ? 'Allowed' : 'Blocked'),
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
