import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/cookie_auto_clear.dart';
import 'package:zerotrust_browser/browser/private_lock.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
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
    this.unloaded = false,
    this.group,
    this.lastUsed,
    this.readerable = false,
    this.reader = false,
    this.javascript = true,
    this.translatedFrom,
    this.translatedTo,
    this.translating = false,
    this.translateDone = 0,
    this.translateTotal = 0,
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

  /// Unloaded to save memory (or not loaded yet after a restart): it
  /// reloads when shown.
  final bool unloaded;

  /// Tab group name, or null.
  final String? group;
  final DateTime? lastUsed;

  /// The page looks like an article reader mode can show.
  final bool readerable;

  /// Showing reader mode.
  final bool reader;

  /// JavaScript on for this page's site.
  final bool javascript;

  /// Shown translated (B16), from and to these languages; null when not.
  final String? translatedFrom;
  final String? translatedTo;

  /// Still translating: [translateDone] of [translateTotal] blocks.
  final bool translating;
  final int translateDone;
  final int translateTotal;

  bool get isStartPage => url == null || url!.isEmpty || url == 'about:blank';

  String get label =>
      (title != null && title!.trim().isNotEmpty) ? title!.trim() : (url ?? '');

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
    bool? unloaded,
    String? Function()? group,
    DateTime? lastUsed,
    bool? readerable,
    bool? reader,
    bool? javascript,
    String? Function()? translatedFrom,
    String? Function()? translatedTo,
    bool? translating,
    int? translateDone,
    int? translateTotal,
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
    unloaded: unloaded ?? this.unloaded,
    group: group != null ? group() : this.group,
    lastUsed: lastUsed ?? this.lastUsed,
    readerable: readerable ?? this.readerable,
    reader: reader ?? this.reader,
    javascript: javascript ?? this.javascript,
    translatedFrom: translatedFrom != null
        ? translatedFrom()
        : this.translatedFrom,
    translatedTo: translatedTo != null ? translatedTo() : this.translatedTo,
    translating: translating ?? this.translating,
    translateDone: translateDone ?? this.translateDone,
    translateTotal: translateTotal ?? this.translateTotal,
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

  /// Group names in use among normal tabs, in order of first appearance.
  List<String> get groups => <String>{
    for (final BrowserTab t in normal)
      if (t.group != null) t.group!,
  }.toList();
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
  Future<BrowserTab> open({
    String? url,
    bool private = false,
    String? group,
  }) async {
    final BrowserTab tab = BrowserTab(
      id: newItemId(),
      private: private,
      url: url,
      group: private ? null : group,
      lastUsed: DateTime.now(),
    );
    state = TabsState(
      tabs: <BrowserTab>[...state.tabs, tab],
      currentId: tab.id,
    );
    await _engine.createTab(tab.id, private: private, url: url);
    await _engine.select(tab.id);
    _queueSave();
    return tab;
  }

  void select(String id) {
    _update(id, (BrowserTab t) => t.copyWith(lastUsed: DateTime.now()));
    state = TabsState(tabs: state.tabs, currentId: id);
    _ensureLive(id).ignore();
    _queueSave();
  }

  /// Reloads an unloaded tab (keeping its history when the engine has it).
  Future<void> _ensureLive(String? id) async {
    if (id == null) return;
    final BrowserTab? t = byId(id);
    if (t == null) return;
    // Shown now, so it counts as used (also the tab restored on start).
    _update(id, (BrowserTab t) => t.copyWith(lastUsed: DateTime.now()));
    if (t.unloaded) {
      _update(id, (BrowserTab t) => t.copyWith(unloaded: false));
      await _engine.createTab(
        id,
        private: t.private,
        url: t.url,
        desktop: t.desktop,
      );
    }
    await _engine.select(id);
    await _engine.requestState(id);
  }

  void setGroup(String id, String? group) {
    final String? name = (group == null || group.trim().isEmpty)
        ? null
        : group.trim();
    _update(id, (BrowserTab t) => t.copyWith(group: () => name));
    _queueSave();
  }

  /// Closes normal tabs not looked at for [days] days (never the one on
  /// screen). Returns how many closed.
  Future<int> closeUnused(int days, {DateTime? now}) async {
    final DateTime cutoff = (now ?? DateTime.now()).subtract(
      Duration(days: days),
    );
    final List<String> old = <String>[
      for (final BrowserTab t in state.normal)
        if (t.id != state.currentId &&
            t.lastUsed != null &&
            t.lastUsed!.isBefore(cutoff))
          t.id,
    ];
    for (final String id in old) {
      await close(id);
    }
    return old.length;
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
    if (current != null && current != id) await _ensureLive(current);
    _queueSave();
    if (closing.private) {
      if (state.private.isEmpty) ref.read(privateLockProvider.notifier).reset();
    } else {
      await sweepSiteData();
    }
  }

  /// B24: wipes data of sites no normal tab shows any more.
  Future<void> sweepSiteData() => ref
      .read(cookieAutoClearProvider)
      .sweep(<String?>[for (final BrowserTab t in state.normal) t.url])
      .catchError((Object _) {});

  Future<void> closeAll({required bool private}) async {
    for (final BrowserTab t in state.tabs.where(
      (BrowserTab t) => t.private == private,
    )) {
      await close(t.id);
    }
  }

  /// Opens a tab showing [html] as the page at [baseUrl] (a saved copy).
  Future<BrowserTab> openHtml(String html, String baseUrl) async {
    final BrowserTab tab = BrowserTab(
      id: newItemId(),
      private: false,
      url: baseUrl,
      loading: true,
      lastUsed: DateTime.now(),
    );
    state = TabsState(
      tabs: <BrowserTab>[...state.tabs, tab],
      currentId: tab.id,
    );
    await _engine.createTab(tab.id, private: false);
    await _engine.select(tab.id);
    await _engine.loadHtml(tab.id, html, baseUrl: baseUrl);
    return tab;
  }

  /// The fire button: closes every tab, normal and private, forgets this
  /// device's saved tabs, and starts again with one new tab.
  Future<void> closeAllForFire() async {
    for (final BrowserTab t in <BrowserTab>[...state.tabs]) {
      await _engine.closeTab(t.id);
    }
    state = const TabsState();
    _saveTimer?.cancel();
    ref.read(privateLockProvider.notifier).reset();
    await ref
        .read(browserDataProvider)
        .saveDeviceTabs(const <SavedTab>[])
        .catchError((Object _) {});
    await open();
  }

  /// Closes every tab (sign out).
  Future<void> closeEverything() async {
    for (final BrowserTab t in <BrowserTab>[...state.tabs]) {
      await _engine.closeTab(t.id);
    }
    state = const TabsState();
    _restored = false;
    ref.read(privateLockProvider.notifier).reset();
  }

  Future<void> load(String id, String url) async {
    final BrowserTab? before = byId(id);
    _update(
      id,
      (BrowserTab t) => t.copyWith(url: url, loading: true, crashed: false),
    );
    if (before != null && before.unloaded) {
      _update(id, (BrowserTab t) => t.copyWith(unloaded: false));
      await _engine.createTab(
        id,
        private: before.private,
        desktop: before.desktop,
      );
    }
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

  /// Reopens this device's tabs from last time, once per unlock. Only the
  /// last one loads now; the others load when shown. Tabs unused for longer
  /// than [closeAfterDays] stay closed.
  Future<void> restoreIfEmpty({int? closeAfterDays, DateTime? now}) async {
    if (_restored) return;
    _restored = true;
    if (state.tabs.isNotEmpty) return;
    final DateTime? cutoff = closeAfterDays == null
        ? null
        : (now ?? DateTime.now()).subtract(Duration(days: closeAfterDays));
    final List<SavedTab> saved = <SavedTab>[
      for (final SavedTab t in await _savedTabs())
        if (cutoff == null || t.lastUsed == null || t.lastUsed!.isAfter(cutoff))
          t,
    ];
    if (saved.isEmpty) {
      await open();
      return;
    }
    final List<BrowserTab> restored = <BrowserTab>[
      for (final SavedTab t in saved)
        BrowserTab(
          id: newItemId(),
          private: false,
          url: t.url,
          title: t.title,
          group: t.group,
          lastUsed: t.lastUsed,
          unloaded: true,
        ),
    ];
    state = TabsState(
      tabs: <BrowserTab>[...state.tabs, ...restored],
      currentId: restored.last.id,
    );
    await _ensureLive(restored.last.id);
  }

  Future<List<SavedTab>> _savedTabs() async {
    try {
      final String me = await ref.read(ztDeviceIdProvider.future);
      final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
      final DeviceTabs? mine = await BrowserCollections.deviceTabs.get(
        store,
        'tabs-$me',
      );
      return mine?.tabs ?? const <SavedTab>[];
    } on Object {
      return const <SavedTab>[];
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
        // For the privacy report: what was blocked since the last update
        // (the count starts again on every new page).
        final int blocked = e.get<int>('blocked') ?? tab.blocked;
        final int more = blocked >= tab.blocked
            ? blocked - tab.blocked
            : blocked;
        if (more > 0) {
          ref
              .read(privacyReportRecorderProvider)
              .add(tab.private ? '' : hostOf(url ?? tab.url), more);
        }
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
            readerable: e.get<bool>('readerable'),
            reader: e.get<bool>('reader'),
            javascript: e.get<bool>('javascript'),
            translatedFrom: () => e.get<String>('translatedFrom'),
            translatedTo: () => e.get<String>('translatedTo'),
            translating: e.get<bool>('translating'),
            translateDone: e.get<int>('translateDone'),
            translateTotal: e.get<int>('translateTotal'),
            clearFavicon: urlChanged && hostOf(url) != hostOf(tab.url),
          ),
        );
        // Browsing in the tab on screen keeps it "used".
        if (urlChanged && e.tabId == state.currentId) {
          _update(
            e.tabId,
            (BrowserTab t) => t.copyWith(lastUsed: DateTime.now()),
          );
        }
        if (urlChanged && !tab.private) {
          _queueSave();
          ref.read(cookieAutoClearProvider).visited(url).ignore();
        }
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
        open(
          url: e.get<String>('url'),
          private: tab.private,
          group: tab.group,
        ).ignore();
      case 'unloaded':
        _update(
          e.tabId,
          (BrowserTab t) => t.copyWith(unloaded: true, loading: false),
        );
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
      final List<SavedTab> open = <SavedTab>[
        for (final BrowserTab t in state.normal)
          if (!t.isStartPage)
            SavedTab(
              url: t.url!,
              title: t.label,
              group: t.group,
              lastUsed: t.lastUsed,
            ),
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
