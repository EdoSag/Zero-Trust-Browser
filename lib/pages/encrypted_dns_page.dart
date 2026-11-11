import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// Android's Private DNS on this network: active, and which server.
final privateDnsProvider = FutureProvider.autoDispose<Map<Object?, Object?>>(
  (ref) => ref.read(browserEngineProvider).privateDns(),
);

/// A Private DNS provider to suggest: its hostname is what goes into
/// Android's setting.
class DnsProvider {
  const DnsProvider(this.name, this.host, this.note);
  final String name;
  final String host;

  /// Short description key: 'blocks' (also blocks ads and trackers) or
  /// 'plain' (just encrypted).
  final String note;
}

/// No-logging providers that need no account (as each one states).
const List<DnsProvider> dnsProviders = <DnsProvider>[
  DnsProvider('Mullvad', 'adblock.dns.mullvad.net', 'blocks'),
  DnsProvider('Quad9', 'dns.quad9.net', 'malware'),
  DnsProvider('Mullvad', 'dns.mullvad.net', 'plain'),
  DnsProvider('Cloudflare', 'one.one.one.one', 'plain'),
];

/// B17: encrypted DNS. Android's Private DNS encrypts the address lookups
/// of every app (DNS over TLS); a browser can't do it better on its own,
/// so this explains it, shows whether it's on, and copies a provider.
class EncryptedDnsPage extends ConsumerWidget {
  const EncryptedDnsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final Map<Object?, Object?> dns =
        ref.watch(privateDnsProvider).value ?? const <Object?, Object?>{};
    final bool active = dns['active'] == true;
    final String? server = dns['server'] as String?;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(l.encryptedDns)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          Card(
            margin: const EdgeInsets.all(16),
            color: active ? scheme.primaryContainer : scheme.errorContainer,
            child: ListTile(
              leading: Icon(active ? Icons.lock_outline : Icons.lock_open),
              title: Text(active ? l.encryptedDnsOn : l.encryptedDnsOff),
              subtitle: Text(
                active
                    ? (server != null
                          ? l.encryptedDnsServer(server)
                          : l.encryptedDnsAutomatic)
                    : l.encryptedDnsOffSub,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l.encryptedDnsExplain),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.encryptedDnsSteps,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          for (final DnsProvider p in dnsProviders)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(switch (p.note) {
                'blocks' => l.dnsBlocksAds(p.name),
                'malware' => l.dnsBlocksMalware(p.name),
                _ => p.name,
              }),
              subtitle: Text(p.host, textDirection: TextDirection.ltr),
              trailing: IconButton(
                tooltip: l.copyHostname,
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.host));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(l.copied)));
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () async {
                await ref.read(browserEngineProvider).openNetworkSettings();
                ref.invalidate(privateDnsProvider);
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(l.openNetworkSettings),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l.encryptedDnsVpnNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
