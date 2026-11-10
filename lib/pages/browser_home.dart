import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/engine/tab_view.dart';
import 'package:zerotrust_browser/pages/bookmarks_page.dart';
import 'package:zerotrust_browser/pages/history_page.dart';
import 'package:zerotrust_browser/pages/settings_page.dart';
import 'package:zerotrust_browser/pages/site_sheet.dart';
import 'package:zerotrust_browser/pages/start_page.dart';
import 'package:zerotrust_browser/pages/tabs_page.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// The browser once unlocked: address bar, the current tab, toolbar.
class BrowserHome extends ConsumerStatefulWidget {
  const BrowserHome({super.key});

  @override
  ConsumerState<BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends ConsumerState<BrowserHome> {
  late final BrowserEngine _engine = ref.read(browserEngineProvider);
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final TextEditingController _findText = TextEditingController();
  StreamSubscription<TabPrompt>? _prompts;
  Completer<void>? _systemUi;
  bool _editing = false;
  bool _finding = false;
  String _findResult = '';
  bool _pruned = false;

  @override
  void initState() {
    super.initState();
    _addressFocus.addListener(() {
      if (!_addressFocus.hasFocus && _editing) setState(() => _editing = false);
    });
    _prompts = ref.read(tabsProvider.notifier).prompts.listen(_onPrompt);
    _engine.pendingLinks.addListener(_openPendingLink);
    _engine.systemUiOpen.addListener(_onSystemUi);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _pushPrivacy(ref.read(browserSettingsProvider));
    await ref.read(tabsProvider.notifier).restoreIfEmpty();
    await _openPendingLink();
  }

  @override
  void dispose() {
    _prompts?.cancel();
    _engine.pendingLinks.removeListener(_openPendingLink);
    _engine.systemUiOpen.removeListener(_onSystemUi);
    _systemUi?.complete();
    _address.dispose();
    _addressFocus.dispose();
    _findText.dispose();
    super.dispose();
  }

  TabsController get _tabs => ref.read(tabsProvider.notifier);
  BrowserSettings get _settings => ref.read(browserSettingsProvider);

  void _pushPrivacy(BrowserSettings s) {
    _engine
        .setPrivacy(
          blockTrackers: s.blockTrackers,
          httpsOnly: s.httpsOnly,
          allowedSites: s.allowedSites,
        )
        .ignore();
  }

  /// The file picker leaves the app; auto-lock waits until it's back.
  void _onSystemUi() {
    if (_engine.systemUiOpen.value) {
      final Completer<void> done = Completer<void>();
      _systemUi = done;
      ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(() => done.future)
          .ignore();
    } else {
      _systemUi?.complete();
      _systemUi = null;
    }
  }

  /// A link or text from another app opens in a new tab.
  Future<void> _openPendingLink() async {
    final String? link = await _engine.consumePendingLink();
    if (link == null || link.trim().isEmpty || !mounted) return;
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    await _tabs.open(url: addressOrSearch(link, _settings.engine));
  }

  // ---- Navigation ----------------------------------------------------------

  Future<void> go(String input) async {
    final String url = addressOrSearch(input, _settings.engine);
    _stopEditing();
    final BrowserTab? tab = ref.read(tabsProvider).current;
    if (tab == null || tab.crashed) {
      await _tabs.open(url: url, private: tab?.private ?? false);
    } else {
      await _tabs.load(tab.id, url);
    }
  }

  void _startEditing(BrowserTab? tab) {
    _address.text = tab?.isStartPage ?? true ? '' : (tab!.url ?? '');
    _address.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _address.text.length,
    );
    setState(() => _editing = true);
    _addressFocus.requestFocus();
  }

  void _stopEditing() {
    _addressFocus.unfocus();
    if (_editing) setState(() => _editing = false);
  }

  Future<void> _onBack(BrowserTab? tab) async {
    if (_editing) return _stopEditing();
    if (_finding) return _closeFind(tab);
    if (tab != null && tab.canGoBack && !tab.isStartPage) {
      await _engine.back(tab.id);
      return;
    }
    // Nothing to go back to: leave like other browsers, tabs stay open.
    await SystemNavigator.pop();
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  // ---- Page prompts --------------------------------------------------------

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onPrompt(TabPrompt p) async {
    if (!mounted) return;
    final TabEvent e = p.event;
    final BrowserTab? tab = _tabs.byId(e.tabId);
    switch (e.type) {
      case 'contextMenu':
        await _linkMenu(e.get<String>('link'), e.get<String>('image'), tab);
      case 'external':
        await _openExternal(e.get<String>('url') ?? '', tab);
      case 'download':
        _snack(
          e.get<bool>('started') == true
              ? 'Downloading ${e.get<String>('name')}'
              : "This file can't be downloaded",
        );
      case 'httpsFailed':
        await _offerInsecure(e.get<String>('url') ?? '', tab);
      case 'sslError':
        _snack(
          "This site's security certificate isn't valid, so it was not opened.",
        );
      case 'find':
        final int count = e.get<int>('count') ?? 0;
        final int active = e.get<int>('active') ?? 0;
        setState(
          () => _findResult = count == 0
              ? (_findText.text.isEmpty ? '' : 'No matches')
              : '${active + 1} of $count',
        );
    }
  }

  Future<void> _linkMenu(String? link, String? image, BrowserTab? tab) async {
    final String? target = link ?? image;
    if (target == null) return;
    final bool private = tab?.private ?? false;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                target,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
            ),
            if (link != null && !private)
              ListTile(
                leading: const Icon(Icons.tab_outlined),
                title: const Text('Open in new tab'),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: link);
                },
              ),
            if (link != null)
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Open in private tab'),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: link, private: true);
                },
              ),
            if (image != null)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Open image in new tab'),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: image, private: private);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(link != null ? 'Copy link' : 'Copy image address'),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: target));
                _snack('Copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheet);
                SharePlus.instance.share(
                  ShareParams(uri: Uri.tryParse(target)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(String url, BrowserTab? tab) async {
    final String scheme = Uri.tryParse(url)?.scheme ?? '';
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: const Text('Open in another app?'),
            content: Text(switch (scheme) {
              'mailto' => 'This link writes an email in your mail app.',
              'tel' => 'This link calls a number with your phone app.',
              _ => 'This page wants to open another app on your phone.',
            }),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Stay here'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Open'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final String? fallback = await _engine.openExternal(url);
    if (fallback != null && tab != null) {
      await _tabs.load(tab.id, fallback);
    } else if (fallback == null && scheme == 'intent') {
      // Opened, or nothing could open it: nothing more to do here.
    }
  }

  Future<void> _offerInsecure(String url, BrowserTab? tab) async {
    if (tab == null) return;
    final String host = hostOf(url);
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            icon: const Icon(Icons.no_encryption_gmailerrorred_outlined),
            title: const Text('Not a secure site'),
            content: Text(
              '$host doesn\'t offer a secure (HTTPS) connection. If you '
              'continue, others on your network can see and change what you '
              'send and receive on this site.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Continue anyway'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Go back'),
              ),
            ],
          ),
        ) ??
        false;
    if (go) {
      await _engine.loadInsecure(tab.id, url);
    } else if (tab.canGoBack) {
      await _engine.back(tab.id);
    }
  }

  // ---- Find in page ---------------------------------------------------------

  void _openFind() {
    setState(() {
      _finding = true;
      _findResult = '';
      _findText.clear();
    });
  }

  void _closeFind(BrowserTab? tab) {
    if (tab != null) _engine.clearFind(tab.id);
    setState(() => _finding = false);
  }

  // ---- Menu ---------------------------------------------------------------

  Future<void> _menu(BrowserTab? tab) async {
    final BrowserData data = ref.read(browserDataProvider);
    final bool onPage = tab != null && !tab.isStartPage && !tab.crashed;
    final Bookmark? saved = onPage ? data.bookmarkFor(tab.url!) : null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) {
        void run(VoidCallback f) {
          Navigator.pop(sheet);
          f();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (onPage)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Forward',
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: tab.canGoForward
                              ? () => run(() => _engine.forward(tab.id))
                              : null,
                        ),
                        IconButton(
                          tooltip: saved == null
                              ? 'Bookmark'
                              : 'Remove bookmark',
                          icon: Icon(
                            saved == null ? Icons.star_border : Icons.star,
                          ),
                          onPressed: () => run(() async {
                            if (saved == null) {
                              await data.addBookmark(tab.url!, tab.label);
                              _snack('Bookmarked');
                            } else {
                              await data.removeBookmark(saved.id);
                              _snack('Bookmark removed');
                            }
                          }),
                        ),
                        IconButton(
                          tooltip: 'Share',
                          icon: const Icon(Icons.share_outlined),
                          onPressed: () => run(
                            () => SharePlus.instance.share(
                              ShareParams(
                                uri: Uri.parse(tab.url!),
                                subject: tab.label,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reload',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => run(() => _engine.reload(tab.id)),
                        ),
                      ],
                    ),
                  ),
                if (onPage) const Divider(),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('New tab'),
                  onTap: () => run(() => _tabs.open()),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('New private tab'),
                  onTap: () => run(() => _tabs.open(private: true)),
                ),
                ListTile(
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: const Text('Bookmarks'),
                  onTap: () =>
                      run(() => _push(BookmarksPage(onOpen: _openFromList))),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('History'),
                  onTap: () =>
                      run(() => _push(HistoryPage(onOpen: _openFromList))),
                ),
                if (onPage)
                  ListTile(
                    leading: const Icon(Icons.find_in_page_outlined),
                    title: const Text('Find in page'),
                    onTap: () => run(_openFind),
                  ),
                if (onPage)
                  SwitchListTile(
                    secondary: const Icon(Icons.desktop_windows_outlined),
                    title: const Text('Desktop site'),
                    value: tab.desktop,
                    onChanged: (bool v) =>
                        run(() => _tabs.setDesktop(tab.id, v)),
                  ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () => run(() => _push(const BrowserSettingsPage())),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens a bookmark or history entry from its page.
  void _openFromList(String url, {bool newTab = false, bool private = false}) {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    final BrowserTab? tab = ref.read(tabsProvider).current;
    if (newTab || private || tab == null) {
      _tabs.open(url: url, private: private);
    } else {
      _tabs.load(tab.id, url);
    }
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(browserSettingsProvider, (_, BrowserSettings next) {
      _pushPrivacy(next);
    });
    // Sync runs while the browser is open.
    ref.watch(ztSyncControllerProvider);
    // Applies "Keep history" once history has loaded.
    ref.listen(historyProvider, (_, AsyncValue<List<HistoryEntry>> next) {
      if (!_pruned && next.hasValue) {
        _pruned = true;
        ref.read(browserDataProvider).pruneHistory().ignore();
      }
    });

    final TabsState tabs = ref.watch(tabsProvider);
    final BrowserTab? tab = tabs.current;
    final bool private = tab?.private ?? false;
    final ThemeData base = Theme.of(context);
    final ThemeData theme = private ? _privateTheme(base) : base;

    return Theme(
      data: theme,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) _onBack(tab);
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                _AddressBar(
                  tab: tab,
                  editing: _editing,
                  controller: _address,
                  focus: _addressFocus,
                  onTap: () => _startEditing(tab),
                  onSubmit: go,
                  onCancel: _stopEditing,
                  onShield: tab == null || tab.isStartPage
                      ? null
                      : () => showSiteSheet(context, ref, tab),
                ),
                if (tab != null && tab.loading && !_editing)
                  LinearProgressIndicator(
                    value: tab.progress <= 0 ? null : tab.progress / 100,
                    minHeight: 2,
                  )
                else
                  const SizedBox(height: 2),
                Expanded(child: _content(tab)),
                if (_finding && tab != null) _findBar(tab),
                _Toolbar(
                  tab: tab,
                  tabCount: private ? tabs.private.length : tabs.normal.length,
                  onBack: tab != null && tab.canGoBack && !tab.isStartPage
                      ? () => _engine.back(tab.id)
                      : null,
                  onHome: () => go(_settings.engine.home),
                  onNewTab: () => _tabs.open(private: private),
                  onTabs: () => _push(TabsPage(startPrivate: private)),
                  onMenu: () => _menu(tab),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BrowserTab? tab) {
    if (_editing) {
      return Suggestions(
        query: _address.text,
        controller: _address,
        onOpen: (String url) => go(url),
      );
    }
    if (tab == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _tabs.open(),
          icon: const Icon(Icons.add),
          label: const Text('New tab'),
        ),
      );
    }
    if (tab.crashed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.sentiment_dissatisfied_outlined, size: 48),
              const SizedBox(height: 16),
              const Text('This page stopped working.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _tabs.revive(tab.id),
                child: const Text('Reload'),
              ),
            ],
          ),
        ),
      );
    }
    if (tab.isStartPage) {
      return StartPage(
        private: tab.private,
        onOpen: (String url) => go(url),
        onSearch: () => _startEditing(tab),
      );
    }
    return TabView(key: ValueKey<String>(tab.id), tabId: tab.id);
  }

  Widget _findBar(BrowserTab tab) {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _findText,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Find in page',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (String t) => _engine.find(tab.id, t),
                onSubmitted: (_) => _engine.findNext(tab.id),
              ),
            ),
            Text(_findResult, style: Theme.of(context).textTheme.bodySmall),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _engine.findNext(tab.id, forward: false),
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _engine.findNext(tab.id),
            ),
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => _closeFind(tab),
            ),
          ],
        ),
      ),
    );
  }
}

/// Private tabs are dark violet, whatever the app theme, so it's always
/// clear which kind of tab is open.
ThemeData _privateTheme(ThemeData base) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6D28D9),
    brightness: Brightness.dark,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    brightness: Brightness.dark,
  );
}

class _AddressBar extends StatelessWidget {
  const _AddressBar({
    required this.tab,
    required this.editing,
    required this.controller,
    required this.focus,
    required this.onTap,
    required this.onSubmit,
    required this.onCancel,
    required this.onShield,
  });

  final BrowserTab? tab;
  final bool editing;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback? onShield;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BrowserTab? t = tab;
    final bool private = t?.private ?? false;
    final Widget leading;
    if (editing) {
      leading = IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.arrow_back),
        onPressed: onCancel,
      );
    } else if (t == null || t.isStartPage) {
      leading = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(
          private ? Icons.privacy_tip_outlined : Icons.search,
          color: scheme.onSurfaceVariant,
        ),
      );
    } else {
      leading = IconButton(
        tooltip: 'Site protection',
        onPressed: onShield,
        icon: Badge(
          isLabelVisible: t.blocked > 0,
          label: Text(t.blocked > 99 ? '99+' : '${t.blocked}'),
          child: Icon(
            t.secure
                ? Icons.shield_outlined
                : Icons.no_encryption_gmailerrorred_outlined,
            color: t.secure ? scheme.primary : scheme.error,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              leading,
              Expanded(
                child: editing
                    ? TextField(
                        controller: controller,
                        focusNode: focus,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        // Typed addresses and searches stay out of the
                        // keyboard's learning.
                        enableIMEPersonalizedLearning: false,
                        decoration: const InputDecoration(
                          hintText: 'Search or type an address',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: onSubmit,
                      )
                    : InkWell(
                        onTap: onTap,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            t == null || t.isStartPage
                                ? (private
                                      ? 'Private tab: search or type an address'
                                      : 'Search or type an address')
                                : displayAddress(t.url),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t == null || t.isStartPage
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
              ),
              if (editing)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: controller.clear,
                )
              else if (private)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tooltip(
                    message:
                        'Private tab: no history, cookies cleared on close',
                    child: Icon(Icons.visibility_off_outlined),
                  ),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.tab,
    required this.tabCount,
    required this.onBack,
    required this.onHome,
    required this.onNewTab,
    required this.onTabs,
    required this.onMenu,
  });

  final BrowserTab? tab;
  final int tabCount;
  final VoidCallback? onBack;
  final VoidCallback onHome;
  final VoidCallback onNewTab;
  final VoidCallback onTabs;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: onHome,
            ),
            IconButton(
              tooltip: 'New tab',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onNewTab,
            ),
            IconButton(
              tooltip: 'Tabs',
              onPressed: onTabs,
              icon: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.onSurface, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tabCount > 99 ? '∞' : '$tabCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bookmarks and history matching what's typed in the address bar.
class Suggestions extends ConsumerWidget {
  const Suggestions({
    super.key,
    required this.query,
    required this.controller,
    required this.onOpen,
  });

  final String query;
  final TextEditingController controller;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final String q = controller.text.trim().toLowerCase();
        final List<Bookmark> bookmarks =
            ref.watch(bookmarksProvider).value ?? const <Bookmark>[];
        final List<HistoryEntry> history =
            ref.watch(historyProvider).value ?? const <HistoryEntry>[];
        bool hit(String url, String title) =>
            q.isEmpty ||
            url.toLowerCase().contains(q) ||
            title.toLowerCase().contains(q);
        final List<Bookmark> b = bookmarks
            .where((Bookmark x) => hit(x.url, x.title))
            .take(q.isEmpty ? 4 : 5)
            .toList();
        final Set<String> shown = b.map((Bookmark x) => x.url).toSet();
        final List<HistoryEntry> h =
            (history
                    .where(
                      (HistoryEntry x) =>
                          hit(x.url, x.title) && !shown.contains(x.url),
                    )
                    .toList()
                  ..sort(
                    (HistoryEntry a, HistoryEntry c) => q.isEmpty
                        ? c.lastVisit.compareTo(a.lastVisit)
                        : c.visits.compareTo(a.visits),
                  ))
                .take(8)
                .toList();
        final SearchEngine engine = ref.watch(browserSettingsProvider).engine;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: <Widget>[
            if (q.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(controller.text.trim()),
                subtitle: Text('Search with ${engine.name}'),
                onTap: () =>
                    onOpen(engine.searchUrl(controller.text.trim()).toString()),
              ),
            for (final Bookmark x in b)
              ListTile(
                leading: SiteIcon(url: x.url, size: 28),
                title: Text(
                  x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  displayAddress(x.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.star, size: 18),
                onTap: () => onOpen(x.url),
              ),
            for (final HistoryEntry x in h)
              ListTile(
                leading: SiteIcon(url: x.url, size: 28),
                title: Text(
                  x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  displayAddress(x.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.history, size: 18),
                onTap: () => onOpen(x.url),
              ),
          ],
        );
      },
    );
  }
}
