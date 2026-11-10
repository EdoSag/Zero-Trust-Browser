import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// One open tab, as the UI shows it. The page itself is a native WebView
/// owned by [BrowserEngine], keyed by [id].
class BrowserTab {
  const BrowserTab({
    required this.id,
    required this.private,
    this.url,
    this.title,
    this.progress = 0,
    this.loading = false,
    this.canGoBack = false,
    this.canGoForward = false,
    this.secure = false,
    this.blocked = 0,
    this.favicon,
    this.crashed = false,
    this.desktop = false,
  });

  final String id;
  final bool private;

  /// Null for a new tab that shows the start page.
  final String? url;
  final String? title;
  final int progress;
  final bool loading;
  final bool canGoBack;
  final bool canGoForward;

  /// https with a valid certificate.
  final bool secure;

  /// Trackers and ads blocked on this page.
  final int blocked;
  final Uint8List? favicon;

  /// The page's process died; it reloads when the user asks.
  final bool crashed;
  final bool desktop;

  bool get isStartPage => url == null || url!.isEmpty || url == 'about:blank';

  String get label => (title != null && title!.trim().isNotEmpty)
      ? title!.trim()
      : (url ?? 'New tab');

  BrowserTab copyWith({
    String? url,
    String? title,
    int? progress,
    bool? loading,
    bool? canGoBack,
    bool? canGoForward,
    bool? secure,
    int? blocked,
    Uint8List? favicon,
    bool clearFavicon = false,
    bool? crashed,
    bool? desktop,
  }) => BrowserTab(
    id: id,
    private: private,
    url: url ?? this.url,
    title: title ?? this.title,
    progress: progress ?? this.progress,
    loading: loading ?? this.loading,
    canGoBack: canGoBack ?? this.canGoBack,
    canGoForward: canGoForward ?? this.canGoForward,
    secure: secure ?? this.secure,
    blocked: blocked ?? this.blocked,
    favicon: clearFavicon ? null : (favicon ?? this.favicon),
    crashed: crashed ?? this.crashed,
    desktop: desktop ?? this.desktop,
  );
}

class TabsState {
  const TabsState({this.tabs = const <BrowserTab>[], this.currentId});

  final List<BrowserTab> tabs;
  final String? currentId;

  BrowserTab? get current {
    for (final BrowserTab t in tabs) {
      if (t.id == currentId) return t;
    }
    return tabs.isEmpty ? null : tabs.last;
  }

  List<BrowserTab> get normal =>
      tabs.where((BrowserTab t) => !t.private).toList();
  List<BrowserTab> get private =>
      tabs.where((BrowserTab t) => t.private).toList();
}

/// Something the page asked for that needs the user: a link menu, another
/// app, an insecure site, a download...
class TabPrompt {
  const TabPrompt(this.event);
  final TabEvent event;
}

/// The open tabs. Lives as long as the app (not just while unlocked), so
/// locking keeps normal tabs where they were. Private tabs close on lock.
class TabsController extends Notifier<TabsState> {
  late BrowserEngine _engine;
  StreamSubscription<TabEvent>? _sub;
  Timer? _saveTimer;
  bool _restored = false;

  /// Page requests the UI shows (link menus, downloads, other apps...).
  final StreamController<TabPrompt> _prompts =
      StreamController<TabPrompt>.broadcast();
  Stream<TabPrompt> get prompts => _prompts.stream;

  @override
  TabsState build() {
    _sub?.cancel();
    _engine = ref.read(browserEngineProvider);
    _sub = _engine.events.listen(_onEvent);
    ref.onDispose(() {
      _sub?.cancel();
      _saveTimer?.cancel();
    });
    return const TabsState();
  }

  BrowserTab? byId(String id) {
    for (final BrowserTab t in state.tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Opens a tab and shows it. [url] null shows the start page.
  Future<BrowserTab> open({String? url, bool private = false}) async {
    final BrowserTab tab = BrowserTab(
      id: newItemId(),
      private: private,
      url: url,
    );
    state = TabsState(
      tabs: <BrowserTab>[...state.tabs, tab],
      currentId: tab.id,
    );
    await _engine.createTab(tab.id, private: private, url: url);
    _queueSave();
    return tab;
  }

  void select(String id) {
    state = TabsState(tabs: state.tabs, currentId: id);
    _engine.requestState(id);
  }

  Future<void> close(String id) async {
    final int index = state.tabs.indexWhere((BrowserTab t) => t.id == id);
    if (index < 0) return;
    final BrowserTab closing = state.tabs[index];
    final List<BrowserTab> rest = <BrowserTab>[...state.tabs]..removeAt(index);
    String? current = state.currentId;
    if (current == id) {
      // Show a neighbour of the same kind, like other browsers do.
      final List<BrowserTab> same = rest
          .where((BrowserTab t) => t.private == closing.private)
          .toList();
      current = same.isNotEmpty
          ? same.last.id
          : (rest.isNotEmpty ? rest.last.id : null);
    }
    state = TabsState(tabs: rest, currentId: current);
    await _engine.closeTab(id);
    _queueSave();
  }

  Future<void> closeAll({required bool private}) async {
    for (final BrowserTab t in state.tabs.where(
      (BrowserTab t) => t.private == private,
    )) {
      await close(t.id);
    }
  }

  /// Closes every tab (sign out).
  Future<void> closeEverything() async {
    for (final BrowserTab t in <BrowserTab>[...state.tabs]) {
      await _engine.closeTab(t.id);
    }
    state = const TabsState();
    _restored = false;
  }

  Future<void> load(String id, String url) async {
    _update(
      id,
      (BrowserTab t) => t.copyWith(url: url, loading: true, crashed: false),
    );
    await _engine.load(id, url);
  }

  /// A crashed tab gets a fresh WebView at the same address.
  Future<void> revive(String id) async {
    final BrowserTab? t = byId(id);
    if (t == null) return;
    _update(id, (BrowserTab t) => t.copyWith(crashed: false, loading: true));
    await _engine.createTab(
      id,
      private: t.private,
      url: t.url,
      desktop: t.desktop,
    );
  }

  Future<void> setDesktop(String id, bool on) async {
    _update(id, (BrowserTab t) => t.copyWith(desktop: on));
    await _engine.setDesktop(id, on);
  }

  /// Reopens this device's tabs from last time, once per unlock.
  Future<void> restoreIfEmpty() async {
    if (_restored) return;
    _restored = true;
    if (state.tabs.isNotEmpty) return;
    final List<({String url, String title})> saved = await _savedTabs();
    if (saved.isEmpty) {
      await open();
      return;
    }
    for (final ({String url, String title}) t in saved) {
      final BrowserTab tab = BrowserTab(
        id: newItemId(),
        private: false,
        url: t.url,
        title: t.title,
      );
      state = TabsState(
        tabs: <BrowserTab>[...state.tabs, tab],
        currentId: tab.id,
      );
      await _engine.createTab(tab.id, private: false, url: t.url);
    }
  }

  Future<List<({String url, String title})>> _savedTabs() async {
    try {
      final String me = await ref.read(ztDeviceIdProvider.future);
      final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
      final DeviceTabs? mine = await BrowserCollections.deviceTabs.get(
        store,
        'tabs-$me',
      );
      return mine?.tabs ?? const <({String url, String title})>[];
    } on Object {
      return const <({String url, String title})>[];
    }
  }

  void _update(String id, BrowserTab Function(BrowserTab) f) {
    final int i = state.tabs.indexWhere((BrowserTab t) => t.id == id);
    if (i < 0) return;
    final List<BrowserTab> next = <BrowserTab>[...state.tabs];
    next[i] = f(next[i]);
    state = TabsState(tabs: next, currentId: state.currentId);
  }

  void _onEvent(TabEvent e) {
    final BrowserTab? tab = byId(e.tabId);
    if (tab == null) return;
    switch (e.type) {
      case 'state':
        final String? url = e.get<String>('url');
        final bool urlChanged = url != null && url != tab.url;
        _update(
          e.tabId,
          (BrowserTab t) => t.copyWith(
            url: url,
            title: e.get<String>('title'),
            progress: e.get<int>('progress'),
            loading: e.get<bool>('loading'),
            canGoBack: e.get<bool>('canGoBack'),
            canGoForward: e.get<bool>('canGoForward'),
            secure: e.get<bool>('secure'),
            blocked: e.get<int>('blocked'),
            desktop: e.get<bool>('desktop'),
            clearFavicon: urlChanged && hostOf(url) != hostOf(tab.url),
          ),
        );
        if (urlChanged && !tab.private) _queueSave();
      case 'favicon':
        final Uint8List? png = e.get<Uint8List>('png');
        if (png != null) {
          _update(e.tabId, (BrowserTab t) => t.copyWith(favicon: png));
        }
      case 'visited':
        if (!tab.private) {
          final String? url = e.get<String>('url');
          if (url != null) {
            ref
                .read(browserDataProvider)
                .recordVisit(url, e.get<String>('title'))
                .ignore();
          }
          _queueSave();
        }
      case 'openTab':
        open(url: e.get<String>('url'), private: tab.private).ignore();
      case 'crashed':
        _update(
          e.tabId,
          (BrowserTab t) => t.copyWith(crashed: true, loading: false),
        );
      default:
        _prompts.add(TabPrompt(e));
    }
  }

  /// Keeps this device's open tabs (never private ones) in the account, so
  /// they come back after a restart and show on the other devices.
  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () {
      final List<({String url, String title})> open =
          <({String url, String title})>[
            for (final BrowserTab t in state.normal)
              if (!t.isStartPage) (url: t.url!, title: t.label),
          ];
      ref
          .read(browserDataProvider)
          .saveDeviceTabs(open)
          .catchError((Object _) {});
    });
  }
}

final tabsProvider = NotifierProvider<TabsController, TabsState>(
  TabsController.new,
);
