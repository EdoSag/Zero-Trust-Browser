import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// "Fill code": ZT Authenticator opens for the site in [tab], the user
/// picks the account (or the one given to the site answers), and the code
/// goes straight into the page. Says how it went, unless the user closed
/// ZT Authenticator without picking.
Future<void> fillCodeFromAuthenticator(
  BuildContext context,
  WidgetRef ref,
  BrowserTab tab,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final AppL10n l = context.l10n;
  final FillCodeResult result = await ref
      .read(browserEngineProvider)
      .fillCode(tab.id);
  final String? text = fillCodeMessage(l, result);
  if (text == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The message for [result], or null when there is nothing to say.
String? fillCodeMessage(AppL10n l, FillCodeResult result) => switch (result) {
  FillCodeResult.filled => l.fillCodeFilled,
  FillCodeResult.missing => l.fillCodeMissing,
  FillCodeResult.canceled => null,
  FillCodeResult.expired => l.fillCodeExpired,
  FillCodeResult.invalid => l.fillCodeInvalid,
  FillCodeResult.moved => l.fillCodeMoved,
  FillCodeResult.noField => l.fillCodeNoField,
  FillCodeResult.unavailable => l.fillCodeUnavailable,
};

/// Above the toolbar while the page asks for a one-time code and ZT
/// Authenticator is on the phone.
class FillCodeBar extends ConsumerWidget {
  const FillCodeBar({super.key, required this.tab, required this.onClose});

  final BrowserTab tab;

  /// Hides the bar for this page.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SizedBox(
        height: 48,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            Icon(Icons.password, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.fillCodeAsked,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => fillCodeFromAuthenticator(context, ref, tab),
              child: Text(l.fillCode),
            ),
            IconButton(
              tooltip: l.close,
              icon: const Icon(Icons.close),
              color: scheme.onSecondaryContainer,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
