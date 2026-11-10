import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// Open tabs: normal (with groups and search), private, and those on the
/// account's other devices.
class TabsPage extends ConsumerStatefulWidget {
  const TabsPage({super.key, this.startPrivate = false});

  final bool startPrivate;

  @override
  ConsumerState<TabsPage> createState() => _TabsPageState();
}

class _TabsPageState extends ConsumerState<TabsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.startPrivate ? 1 : 0,
  );
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  /// Groups shown folded.
  final Set<String> _folded = <String>{};

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  TabsController get _controller => ref.read(tabsProvider.notifier);
  AppL10n get l => context.l10n;

  void _show(String id) {
    _controller.select(id);
    Navigator.of(context).pop();
  }

  Future<void> _new({required bool private, String? group}) async {
    await _controller.open(private: private, group: group);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickGroup(BrowserTab t) async {
    final List<String> groups = ref.read(tabsProvider).groups;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final String g in groups)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(g),
                selected: g == t.group,
                onTap: () => Navigator.pop(sheet, g),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l.newGroup),
              onTap: () async {
                final String? name = await _askName(sheet, l.newGroup, '');
                if (sheet.mounted) Navigator.pop(sheet, name);
              },
            ),
            if (t.group != null)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: Text(l.removeFromGroup),
                onTap: () => Navigator.pop(sheet, ''),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _controller.setGroup(t.id, picked);
  }

  Future<String?> _askName(BuildContext ctx, String title, String start) {
    final TextEditingController name = TextEditingController(text: start);
    return showDialog<String>(
      context: ctx,
      builder: (BuildContext d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l.groupName),
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

  Future<void> _groupMenu(String group, List<BrowserTab> tabs) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l.newTabInGroup),
              onTap: () => Navigator.pop(sheet, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.renameGroup),
              onTap: () => Navigator.pop(sheet, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(l.ungroupTabs),
              onTap: () => Navigator.pop(sheet, 'ungroup'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(l.closeNTabs(tabs.length)),
              onTap: () => Navigator.pop(sheet, 'close'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'new':
        await _new(private: false, group: group);
      case 'rename':
        if (!mounted) return;
        final String? name = await _askName(context, l.renameGroup, group);
        if (name == null || name.isEmpty) return;
        for (final BrowserTab t in tabs) {
          _controller.setGroup(t.id, name);
        }
      case 'ungroup':
        for (final BrowserTab t in tabs) {
          _controller.setGroup(t.id, null);
        }
      case 'close':
        for (final BrowserTab t in tabs) {
          await _controller.close(t.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final TabsState state = ref.watch(tabsProvider);
    final List<DeviceTabs> others =
        ref.watch(otherDevicesTabsProvider).value ?? const <DeviceTabs>[];
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.searchTabs,
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : Text(l.tabs),
        actions: <Widget>[
          IconButton(
            tooltip: _searching ? l.stopSearching : l.searchTabs,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _search.clear();
            }),
          ),
          ListenableBuilder(
            listenable: _tabs,
            builder: (BuildContext context, _) => _tabs.index == 2
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: _tabs.index == 1
                        ? l.closeAllPrivateTabs
                        : l.closeAllTabs,
                    icon: const Icon(Icons.clear_all),
                    onPressed: () =>
                        _controller.closeAll(private: _tabs.index == 1),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: l.tabsCount(state.normal.length)),
            Tab(text: l.privateCount(state.private.length)),
            Tab(text: l.otherDevices),
          ],
        ),
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabs,
        builder: (BuildContext context, _) => _tabs.index == 2
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => _new(private: _tabs.index == 1),
                icon: const Icon(Icons.add),
                label: Text(_tabs.index == 1 ? l.privateTab : l.newTab),
              ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _list(state.normal, state.currentId, l.noOpenTabs, groups: true),
          _list(state.private, state.currentId, l.privateTabsExplain),
          _otherDevices(others),
        ],
      ),
    );
  }

  bool _matches(BrowserTab t, String q) =>
      q.isEmpty ||
      t.label.toLowerCase().contains(q) ||
      (t.url?.toLowerCase().contains(q) ?? false) ||
      (t.group?.toLowerCase().contains(q) ?? false);

  Widget _list(
    List<BrowserTab> all,
    String? currentId,
    String empty, {
    bool groups = false,
  }) {
    final String q = _search.text.trim().toLowerCase();
    final List<BrowserTab> tabs = all
        .where((BrowserTab t) => _matches(t, q))
        .toList();
    if (tabs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            all.isEmpty ? empty : l.noTabsMatch,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final List<Widget> children = <Widget>[];
    if (groups && q.isEmpty) {
      final Map<String, List<BrowserTab>> byGroup =
          <String, List<BrowserTab>>{};
      for (final BrowserTab t in tabs) {
        if (t.group != null) {
          byGroup.putIfAbsent(t.group!, () => <BrowserTab>[]).add(t);
        }
      }
      for (final MapEntry<String, List<BrowserTab>> g in byGroup.entries) {
        children.add(_groupHeader(g.key, g.value));
        if (!_folded.contains(g.key)) {
          for (final BrowserTab t in g.value.reversed) {
            children.add(_tile(t, currentId));
          }
        }
      }
      final List<BrowserTab> loose = tabs
          .where((BrowserTab t) => t.group == null)
          .toList();
      if (byGroup.isNotEmpty && loose.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Text(
              l.notInGroup,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        );
      }
      for (final BrowserTab t in loose.reversed) {
        children.add(_tile(t, currentId));
      }
    } else {
      for (final BrowserTab t in tabs.reversed) {
        children.add(_tile(t, currentId));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: children,
    );
  }

  Widget _groupHeader(String group, List<BrowserTab> tabs) {
    final bool folded = _folded.contains(group);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(folded ? Icons.folder_outlined : Icons.folder_open),
      title: Text(group, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(l.nTabs(tabs.length)),
      onTap: () => setState(() {
        if (!_folded.remove(group)) _folded.add(group);
      }),
      trailing: IconButton(
        tooltip: l.groupOptions,
        icon: const Icon(Icons.more_vert),
        onPressed: () => _groupMenu(group, tabs),
      ),
    );
  }

  Widget _tile(BrowserTab t, String? currentId) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey<String>(t.id),
      onDismissed: (_) => _controller.close(t.id),
      child: Card(
        color: t.id == currentId ? scheme.secondaryContainer : null,
        child: ListTile(
          leading: SiteIcon(url: t.url, favicon: t.favicon),
          title: Text(
            t.isStartPage ? l.newTab : t.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: t.isStartPage ? null : AddressText(displayAddress(t.url)),
          trailing: IconButton(
            tooltip: l.closeTab,
            icon: const Icon(Icons.close),
            onPressed: () => _controller.close(t.id),
          ),
          onTap: () => _show(t.id),
          onLongPress: t.private ? null : () => _pickGroup(t),
        ),
      ),
    );
  }

  Widget _otherDevices(List<DeviceTabs> others) {
    if (others.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.otherDevicesEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final String q = _search.text.trim().toLowerCase();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        for (final DeviceTabs d in others) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(
              d.deviceName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final SavedTab t in d.tabs)
            if (q.isEmpty ||
                t.title.toLowerCase().contains(q) ||
                t.url.toLowerCase().contains(q))
              ListTile(
                leading: SiteIcon(url: t.url),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: AddressText(displayAddress(t.url)),
                onTap: () async {
                  await _controller.open(url: t.url);
                  if (mounted) Navigator.of(context).pop();
                },
              ),
        ],
      ],
    );
  }
}
