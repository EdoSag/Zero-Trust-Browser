import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// Open tabs: normal, private, and those on the account's other devices.
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

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  TabsController get _controller => ref.read(tabsProvider.notifier);

  void _show(String id) {
    _controller.select(id);
    Navigator.of(context).pop();
  }

  Future<void> _new({required bool private}) async {
    await _controller.open(private: private);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TabsState state = ref.watch(tabsProvider);
    final List<DeviceTabs> others =
        ref.watch(otherDevicesTabsProvider).value ?? const <DeviceTabs>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tabs'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _tabs,
            builder: (BuildContext context, _) => _tabs.index == 2
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: _tabs.index == 1
                        ? 'Close all private tabs'
                        : 'Close all tabs',
                    icon: const Icon(Icons.clear_all),
                    onPressed: () =>
                        _controller.closeAll(private: _tabs.index == 1),
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: 'Tabs (${state.normal.length})'),
            Tab(text: 'Private (${state.private.length})'),
            const Tab(text: 'Other devices'),
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
                label: Text(_tabs.index == 1 ? 'Private tab' : 'New tab'),
              ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _list(state.normal, state.currentId, 'No open tabs'),
          _list(
            state.private,
            state.currentId,
            'Private tabs keep no history, and their cookies are deleted '
            'when the last one closes or the app locks.',
          ),
          _otherDevices(others),
        ],
      ),
    );
  }

  Widget _list(List<BrowserTab> tabs, String? currentId, String empty) {
    if (tabs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(empty, textAlign: TextAlign.center),
        ),
      );
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: <Widget>[
        for (final BrowserTab t in tabs.reversed)
          Dismissible(
            key: ValueKey<String>(t.id),
            onDismissed: (_) => _controller.close(t.id),
            child: Card(
              color: t.id == currentId ? scheme.secondaryContainer : null,
              child: ListTile(
                leading: SiteIcon(url: t.url, favicon: t.favicon),
                title: Text(
                  t.isStartPage ? 'New tab' : t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: t.isStartPage
                    ? null
                    : Text(
                        displayAddress(t.url),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: IconButton(
                  tooltip: 'Close tab',
                  icon: const Icon(Icons.close),
                  onPressed: () => _controller.close(t.id),
                ),
                onTap: () => _show(t.id),
              ),
            ),
          ),
      ],
    );
  }

  Widget _otherDevices(List<DeviceTabs> others) {
    if (others.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Tabs open in ZT Browser on your other devices show here, '
            'end-to-end encrypted. Private tabs are never shared.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
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
          for (final ({String url, String title}) t in d.tabs)
            ListTile(
              leading: SiteIcon(url: t.url),
              title: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                displayAddress(t.url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
