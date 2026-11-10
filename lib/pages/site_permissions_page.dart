import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';

/// Lets the user change a remembered camera, microphone or location answer:
/// allow, block, or ask again next time.
Future<void> editSitePermission(
  BuildContext context,
  WidgetRef ref,
  String host,
  String kind,
) async {
  final BrowserSettings s = ref.read(browserSettingsProvider);
  const String ask = 'ask';
  final bool? now = s.permissionFor(host, kind);
  final String? picked = await showDialog<String>(
    context: context,
    builder: (BuildContext d) => SimpleDialog(
      title: Text('${SitePermission.label(kind)} on $host'),
      children: <Widget>[
        RadioGroup<String>(
          groupValue: now == null ? ask : (now ? 'allow' : 'block'),
          onChanged: (String? v) => Navigator.of(d).pop(v),
          child: const Column(
            children: <Widget>[
              RadioListTile<String>(value: 'allow', title: Text('Allow')),
              RadioListTile<String>(value: 'block', title: Text('Block')),
              RadioListTile<String>(value: ask, title: Text('Ask next time')),
            ],
          ),
        ),
      ],
    ),
  );
  if (picked == null) return;
  await ref
      .read(browserDataProvider)
      .saveSettings(
        s.withPermission(host, kind, switch (picked) {
          'allow' => true,
          'block' => false,
          _ => null,
        }),
      );
}

/// Sites you allowed or blocked from using your camera, microphone or
/// location. Synced, so every device remembers the same answers.
class SitePermissionsPage extends ConsumerWidget {
  const SitePermissionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final List<String> hosts = s.sitePermissions.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Site permissions')),
      body: hosts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'When a site asks for your camera, microphone or location, '
                  'ZT Browser asks you first. Answers you choose to remember '
                  'show here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: <Widget>[
                for (final String host in hosts)
                  ListTile(
                    title: Text(host),
                    subtitle: Wrap(
                      spacing: 8,
                      children: <Widget>[
                        for (final MapEntry<String, bool> p
                            in s.sitePermissions[host]!.entries)
                          ActionChip(
                            avatar: Icon(
                              p.value ? Icons.check : Icons.block,
                              size: 18,
                            ),
                            label: Text(
                              '${SitePermission.label(p.key)}: '
                              '${p.value ? 'allowed' : 'blocked'}',
                            ),
                            onPressed: () =>
                                editSitePermission(context, ref, host, p.key),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: 'Forget',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        BrowserSettings next = s;
                        for (final String kind
                            in s.sitePermissions[host]!.keys) {
                          next = next.withPermission(host, kind, null);
                        }
                        ref.read(browserDataProvider).saveSettings(next);
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
