import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

typedef OpenUrl = void Function(String url, {bool newTab, bool private});

/// Bookmarks, end-to-end encrypted and synced across the account's devices.
class BookmarksPage extends ConsumerStatefulWidget {
  const BookmarksPage({super.key, required this.onOpen});

  final OpenUrl onOpen;

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  String _query = '';

  Future<void> _edit(Bookmark b) async {
    final TextEditingController title = TextEditingController(text: b.title);
    final TextEditingController url = TextEditingController(text: b.url);
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: const Text('Edit bookmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Address'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true && url.text.trim().isNotEmpty) {
      await ref
          .read(browserDataProvider)
          .saveBookmark(
            b.copyWith(title: title.text.trim(), url: url.text.trim()),
          );
    }
    title.dispose();
    url.dispose();
  }

  Future<void> _remove(Bookmark b) async {
    final BrowserData data = ref.read(browserDataProvider);
    await data.removeBookmark(b.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bookmark removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => data.saveBookmark(b),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Bookmark>> all = ref.watch(bookmarksProvider);
    final String q = _query.toLowerCase();
    final List<Bookmark> shown = (all.value ?? const <Bookmark>[])
        .where(
          (Bookmark b) =>
              q.isEmpty ||
              b.title.toLowerCase().contains(q) ||
              b.url.toLowerCase().contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search bookmarks',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll<double>(0),
              onChanged: (String v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: all.isLoading && !all.hasValue
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        q.isEmpty
                            ? 'No bookmarks yet. Tap the star in the menu to '
                                  'save a page. Bookmarks are end-to-end '
                                  'encrypted and on all your devices.'
                            : 'No bookmarks match.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Bookmark b = shown[i];
                      return Dismissible(
                        key: ValueKey<String>(b.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => _remove(b),
                        child: ListTile(
                          leading: SiteIcon(url: b.url),
                          title: Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            displayAddress(b.url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => widget.onOpen(b.url),
                          trailing: PopupMenuButton<String>(
                            onSelected: (String v) => switch (v) {
                              'tab' => widget.onOpen(b.url, newTab: true),
                              'private' => widget.onOpen(b.url, private: true),
                              'edit' => _edit(b),
                              _ => _remove(b),
                            },
                            itemBuilder: (_) => const <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'tab',
                                child: Text('Open in new tab'),
                              ),
                              PopupMenuItem<String>(
                                value: 'private',
                                child: Text('Open in private tab'),
                              ),
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
