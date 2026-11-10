import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/app/browser_config.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// What a new tab shows: a search box, favourite sites from bookmarks, and
/// for private tabs, what private means.
class StartPage extends ConsumerWidget {
  const StartPage({
    super.key,
    required this.private,
    required this.onOpen,
    required this.onSearch,
  });

  final bool private;
  final ValueChanged<String> onOpen;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final List<Bookmark> bookmarks =
        ref.watch(bookmarksProvider).value ?? const <Bookmark>[];
    final SearchEngine engine = ref.watch(browserSettingsProvider).engine;
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
          private ? 'Private tab' : 'ZT Browser',
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
                  Text(
                    'Search with ${engine.name}',
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (!private &&
            !ref.watch(browserSettingsProvider).autofillTipDismissed)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.password, color: scheme.primary),
                      const SizedBox(width: 12),
                      Text('Your passwords', style: text.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ZT Browser never stores passwords. Your password '
                    'manager (Bitwarden, Proton Pass, 1Password...) fills '
                    "sign-in forms through Android's autofill, in private "
                    'tabs too.',
                    style: text.bodyMedium,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => ref
                            .read(browserEngineProvider)
                            .openAutofillSettings(),
                        child: const Text('Choose in Android'),
                      ),
                      TextButton(
                        onPressed: () {
                          final BrowserSettings s = ref.read(
                            browserSettingsProvider,
                          );
                          ref
                              .read(browserDataProvider)
                              .saveSettings(
                                s.copyWith(autofillTipDismissed: true),
                              );
                        },
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (private)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Pages you open here are not saved to your history. Cookies '
                'and site data are kept apart from your normal tabs and '
                'deleted when you close the last private tab or the app '
                'locks. Downloads and bookmarks you add are kept.\n\n'
                'Private tabs hide your browsing on this phone. Sites, your '
                'network and your internet provider can still see your visits.',
                style: text.bodyMedium,
              ),
            ),
          )
        else if (bookmarks.isNotEmpty) ...<Widget>[
          Text('Bookmarks', style: text.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 16,
            children: <Widget>[
              for (final Bookmark b in bookmarks.take(12))
                SizedBox(
                  width: 76,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(b.url),
                    child: Column(
                      children: <Widget>[
                        SiteIcon(url: b.url, size: 44),
                        const SizedBox(height: 6),
                        Text(
                          b.title.isEmpty ? hostOf(b.url) : b.title,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ] else
          Text(
            'Trackers and ads are blocked on every site. Your bookmarks '
            'and history are end-to-end encrypted in your Zero-Trust '
            'account: only your devices can read them.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
