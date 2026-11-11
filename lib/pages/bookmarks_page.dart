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

  /// The folder open now, or null for the top level.
  String? _folder;
  AppL10n get l => context.l10n;
  BrowserData get _data => ref.read(browserDataProvider);

  Future<String?> _askName(String title, String start) {
    final TextEditingController name = TextEditingController(text: start);
    return showDialog<String>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l.folderName),
          onSubmitted: (String v) => Navigator.pop(d, v.trim()),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(d), child: Text(l.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(d, name.text.trim()),
            child: Text(l.save),
          ),
        ],
      ),
    ).whenComplete(name.dispose);
  }

  Future<void> _newFolder() async {
    final String? name = await _askName(l.newFolder, '');
    if (name == null || name.isEmpty) return;
    await _data.addFolder(name);
  }

  Future<void> _folderMenu(String folder, int count) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.renameFolder),
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: Text(l.deleteFolder),
              subtitle: count == 0 ? null : Text(l.deleteFolderKeeps(count)),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'rename':
        final String? name = await _askName(l.renameFolder, folder);
        if (name == null || name.isEmpty) return;
        await _data.renameFolder(folder, name);
        if (_folder == folder) setState(() => _folder = name);
      case 'delete':
        await _data.deleteFolder(folder);
        if (_folder == folder) setState(() => _folder = null);
    }
  }

  Future<void> _moveTo(Bookmark b) async {
    final List<String> folders = ref
        .read(browserSettingsProvider)
        .foldersWith(ref.read(bookmarksProvider).value ?? const <Bookmark>[]);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: Text(l.topLevel),
                selected: b.folder == null,
                onTap: () => Navigator.pop(sheet, ''),
              ),
              for (final String f in folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f),
                  selected: b.folder == f,
                  onTap: () => Navigator.pop(sheet, f),
                ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(l.newFolder),
                onTap: () async {
                  final String? name = await _askName(l.newFolder, '');
                  if (sheet.mounted) Navigator.pop(sheet, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final String? to = picked.isEmpty ? null : picked;
    if (to != null) await _data.addFolder(to);
    if (to == b.folder) return;
    await _data.moveBookmark(b, to);
  }

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
    final List<Bookmark> bookmarks = all.value ?? const <Bookmark>[];
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final List<String> folders = s.foldersWith(bookmarks);
    final String q = _query.toLowerCase();
    final bool searching = q.isNotEmpty;
    final String? folder = _folder;

    final Widget list;
    if (all.isLoading && !all.hasValue) {
      list = const Center(child: CircularProgressIndicator());
    } else if (searching) {
      final List<Bookmark> found = bookmarks
          .where(
            (Bookmark b) =>
                b.title.toLowerCase().contains(q) ||
                b.url.toLowerCase().contains(q) ||
                (b.folder?.toLowerCase().contains(q) ?? false),
          )
          .toList();
      list = found.isEmpty
          ? _empty(l.noBookmarksMatch)
          : ListView(
              children: <Widget>[
                for (final Bookmark b in found) _tile(b, showFolder: true),
              ],
            );
    } else {
      final List<Bookmark> here = bookmarks
          .where((Bookmark b) => b.folder == folder)
          .toList();
      final List<String> shownFolders = folder == null
          ? folders
          : const <String>[];
      if (here.isEmpty && shownFolders.isEmpty) {
        list = _empty(folder == null ? l.noBookmarksYet : l.folderEmpty);
      } else {
        // Folders first, then bookmarks; each drags within its own kind.
        final int nf = shownFolders.length;
        list = ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: nf + here.length,
          onReorderItem: (int from, int to) {
            if (from < nf) {
              final List<String> next = <String>[...shownFolders];
              final String f = next.removeAt(from);
              next.insert(to.clamp(0, nf - 1), f);
              _data.reorderFolders(next);
            } else {
              final List<Bookmark> next = <Bookmark>[...here];
              final Bookmark b = next.removeAt(from - nf);
              next.insert((to - nf).clamp(0, next.length), b);
              _data.reorderBookmarks(next);
            }
          },
          itemBuilder: (BuildContext context, int i) {
            if (i < nf) {
              final String f = shownFolders[i];
              final int count = bookmarks
                  .where((Bookmark b) => b.folder == f)
                  .length;
              return ListTile(
                key: ValueKey<String>('folder:$f'),
                leading: const Icon(Icons.folder_outlined),
                title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(l.nBookmarks(count)),
                onTap: () => setState(() => _folder = f),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: l.folderOptions,
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _folderMenu(f, count),
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_handle,
                          semanticLabel: l.dragToReorder,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final Bookmark b = here[i - nf];
            return KeyedSubtree(
              key: ValueKey<String>(b.id),
              child: _tile(b, dragIndex: i),
            );
          },
        );
      }
    }

    return PopScope(
      canPop: folder == null || searching,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && folder != null) setState(() => _folder = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(folder ?? l.bookmarks),
          leading: folder == null
              ? null
              : BackButton(onPressed: () => setState(() => _folder = null)),
          actions: <Widget>[
            if (folder == null)
              IconButton(
                tooltip: l.newFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _newFolder,
              )
            else
              IconButton(
                tooltip: l.folderOptions,
                icon: const Icon(Icons.more_vert),
                onPressed: () => _folderMenu(
                  folder,
                  bookmarks.where((Bookmark b) => b.folder == folder).length,
                ),
              ),
            if (folder == null)
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
            Expanded(child: list),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );

  Widget _tile(Bookmark b, {bool showFolder = false, int? dragIndex}) {
    return Dismissible(
      key: ValueKey<String>('dismiss:${b.id}'),
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
        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: showFolder && b.folder != null
            ? Text(
                '${b.folder} · ${displayAddress(b.url)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : AddressText(displayAddress(b.url)),
        onTap: () => widget.onOpen(b.url),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PopupMenuButton<String>(
              onSelected: (String v) => switch (v) {
                'tab' => widget.onOpen(b.url, newTab: true),
                'private' => widget.onOpen(b.url, private: true),
                'edit' => _edit(b),
                'move' => _moveTo(b),
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
                PopupMenuItem<String>(value: 'edit', child: Text(l.edit)),
                PopupMenuItem<String>(
                  value: 'move',
                  child: Text(l.moveToFolder),
                ),
                PopupMenuItem<String>(value: 'delete', child: Text(l.delete)),
              ],
            ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.drag_handle,
                    semanticLabel: l.dragToReorder,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
