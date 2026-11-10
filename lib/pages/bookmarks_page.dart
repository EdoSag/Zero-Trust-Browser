import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/bookmark_import.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
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
  AppL10n get l => context.l10n;

  Future<void> _edit(Bookmark b) async {
    final TextEditingController title = TextEditingController(text: b.title);
    final TextEditingController url = TextEditingController(text: b.url);
    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text(l.editBookmark),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: title,
              decoration: InputDecoration(labelText: l.name),
            ),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l.address),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(l.save),
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
        content: Text(l.bookmarkRemoved),
        // Flutter keeps a snackbar with an action open until it is tapped.
        persist: false,
        action: SnackBarAction(
          label: l.undo,
          onPressed: () => data.saveBookmark(b),
        ),
      ),
    );
  }

  /// Bookmarks exported from Chrome, Firefox, Edge or Safari (an .html
  /// file), added to the account; ones already saved are skipped.
  Future<void> _import() async {
    final AppL10n l = this.l;
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: Text(l.importBookmarks),
            content: SingleChildScrollView(child: Text(l.importExplain)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(l.pickFile),
              ),
            ],
          ),
        ) ??
        false;
    if (!go) return;
    final Uint8List? bytes = await ref.read(browserEngineProvider).pickFile(
      const <String>['text/html', 'application/xhtml+xml', '*/*'],
    );
    if (bytes == null || !mounted) return;
    final List<Bookmark> found = parseBookmarksHtml(
      utf8.decode(bytes, allowMalformed: true),
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (found.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.noBookmarksInFile)));
      return;
    }
    final int added = await ref
        .read(browserDataProvider)
        .importBookmarks(found);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added == 0 ? l.allAlreadySaved(found.length) : l.importedCount(added),
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
              b.url.toLowerCase().contains(q) ||
              (b.folder?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.bookmarks),
        actions: <Widget>[
          IconButton(
            tooltip: l.importBookmarks,
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _import,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: l.searchBookmarks,
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
                        q.isEmpty ? l.noBookmarksYet : l.noBookmarksMatch,
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
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsetsDirectional.only(end: 24),
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
                          subtitle: b.folder == null
                              ? AddressText(displayAddress(b.url))
                              : Text(
                                  '${b.folder} · ${displayAddress(b.url)}',
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
                            itemBuilder: (_) => <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'tab',
                                child: Text(l.openInNewTab),
                              ),
                              PopupMenuItem<String>(
                                value: 'private',
                                child: Text(l.openInPrivateTab),
                              ),
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Text(l.edit),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text(l.delete),
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
