import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// Opens a reading list item: the live page, or its saved copy.
typedef OpenReading = void Function(ReadingItem item, {required bool saved});

/// Pages saved to read later. Their text is kept encrypted in the account
/// so they open without a connection, on every device.
class ReadingListPage extends ConsumerWidget {
  const ReadingListPage({super.key, required this.onOpen});

  final OpenReading onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final AsyncValue<List<ReadingItem>> items = ref.watch(readingListProvider);
    final BrowserData data = ref.read(browserDataProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.readingList)),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text(l.readingListError)),
        data: (List<ReadingItem> list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l.readingListEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView(
            children: <Widget>[
              for (final ReadingItem r in list)
                Dismissible(
                  key: ValueKey<String>(r.id),
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                  ),
                  onDismissed: (_) => data.removeFromReadingList(r).ignore(),
                  child: ListTile(
                    leading: SiteIcon(url: r.url),
                    title: Text(
                      r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: r.read
                          ? TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            )
                          : const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        AddressText(displayAddress(r.url)),
                        if (r.saved != null) Text(l.savedOffline),
                      ],
                    ),
                    onTap: () {
                      data.setRead(r, true).ignore();
                      onOpen(r, saved: false);
                    },
                    trailing: PopupMenuButton<String>(
                      tooltip: l.more,
                      onSelected: (String v) {
                        switch (v) {
                          case 'saved':
                            data.setRead(r, true).ignore();
                            onOpen(r, saved: true);
                          case 'read':
                            data.setRead(r, !r.read).ignore();
                          case 'remove':
                            data.removeFromReadingList(r).ignore();
                        }
                      },
                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                        if (r.saved != null)
                          PopupMenuItem<String>(
                            value: 'saved',
                            child: Text(l.openSavedCopy),
                          ),
                        PopupMenuItem<String>(
                          value: 'read',
                          child: Text(r.read ? l.markUnread : l.markRead),
                        ),
                        PopupMenuItem<String>(
                          value: 'remove',
                          child: Text(l.remove),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
