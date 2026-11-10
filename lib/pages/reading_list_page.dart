import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
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
    final AsyncValue<List<ReadingItem>> items = ref.watch(readingListProvider);
    final BrowserData data = ref.read(browserDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reading list')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) =>
            const Center(child: Text("The reading list couldn't load.")),
        data: (List<ReadingItem> list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Save pages from the menu with "Add to reading list". '
                  'Articles are kept to read offline, end-to-end encrypted '
                  'in your account.',
                  textAlign: TextAlign.center,
                ),
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
                    subtitle: Text(
                      <String>[
                        displayAddress(r.url),
                        if (r.saved != null) 'Saved offline',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      data.setRead(r, true).ignore();
                      onOpen(r, saved: false);
                    },
                    trailing: PopupMenuButton<String>(
                      tooltip: 'More',
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
                          const PopupMenuItem<String>(
                            value: 'saved',
                            child: Text('Open saved copy'),
                          ),
                        PopupMenuItem<String>(
                          value: 'read',
                          child: Text(r.read ? 'Mark unread' : 'Mark read'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'remove',
                          child: Text('Remove'),
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
