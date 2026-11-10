import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// Asks for a shortcut's name and address. Returns null when cancelled.
Future<Shortcut?> askShortcut(BuildContext context, {Shortcut? start}) {
  return showDialog<Shortcut>(
    context: context,
    builder: (_) => _ShortcutDialog(start: start),
  );
}

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({this.start});

  final Shortcut? start;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.start?.title ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.start?.url ?? '',
  );
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _done() {
    final String? url = webAddress(_url.text);
    if (url == null) {
      setState(() => _invalid = true);
      return;
    }
    final String name = _name.text.trim();
    Navigator.pop(
      context,
      Shortcut(url: url, title: name.isEmpty ? hostOf(url) : name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    return AlertDialog(
      title: Text(widget.start == null ? l.addShortcut : l.editShortcut),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _url,
              autofocus: widget.start == null,
              keyboardType: TextInputType.url,
              autocorrect: false,
              // Addresses read left to right in every language.
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: l.address,
                hintText: 'example.com',
                errorText: _invalid ? l.shortcutInvalid : null,
              ),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
            ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l.name),
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
        FilledButton(onPressed: _done, child: Text(l.save)),
      ],
    );
  }
}

/// The sites pinned to the start page: add, rename, remove, and drag into
/// the order you like. Synced with the other settings.
class ShortcutsPage extends ConsumerWidget {
  const ShortcutsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final BrowserData data = ref.read(browserDataProvider);
    final List<Shortcut> shortcuts = s.shortcuts;

    Future<void> add() async {
      final Shortcut? made = await askShortcut(context);
      if (made == null) return;
      await data.saveSettings(
        ref.read(browserSettingsProvider).withShortcut(made.url, made.title),
      );
    }

    Future<void> edit(int index) async {
      final Shortcut? made = await askShortcut(
        context,
        start: shortcuts[index],
      );
      if (made == null) return;
      final List<Shortcut> next = <Shortcut>[
        ...ref.read(browserSettingsProvider).shortcuts,
      ];
      if (index >= next.length) return;
      next[index] = made;
      await data.saveSettings(
        ref.read(browserSettingsProvider).copyWith(shortcuts: next),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.shortcuts)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: add,
        icon: const Icon(Icons.add),
        label: Text(l.addShortcut),
      ),
      body: shortcuts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.shortcutsEmpty, textAlign: TextAlign.center),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  l.dragToReorder,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              itemCount: shortcuts.length,
              onReorderItem: (int from, int to) {
                final List<Shortcut> next = <Shortcut>[...shortcuts];
                next.insert(to, next.removeAt(from));
                data.saveSettings(s.copyWith(shortcuts: next));
              },
              itemBuilder: (BuildContext context, int i) {
                final Shortcut sc = shortcuts[i];
                return ListTile(
                  key: ValueKey<String>('${sc.url}#$i'),
                  leading: SiteIcon(url: sc.url),
                  title: Text(
                    sc.title.isEmpty ? hostOf(sc.url) : sc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: AddressText(displayAddress(sc.url)),
                  onTap: () => edit(i),
                  trailing: IconButton(
                    tooltip: l.remove,
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        data.saveSettings(s.withoutShortcut(sc.url)),
                  ),
                );
              },
            ),
    );
  }
}
