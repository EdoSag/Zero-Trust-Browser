import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/apply_settings.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';
import 'package:zerotrust_browser/browser/filter_lists.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/browser/private_lock.dart';
import 'package:zerotrust_browser/browser/read_aloud.dart';
import 'package:zerotrust_browser/browser/reader.dart';
import 'package:zerotrust_browser/browser/search_suggestions.dart';
import 'package:zerotrust_browser/browser/site_permissions.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/browser/zt_apps.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/engine/tab_view.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/bookmarks_page.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';
import 'package:zerotrust_browser/pages/history_page.dart';
import 'package:zerotrust_browser/pages/privacy_report_page.dart';
import 'package:zerotrust_browser/pages/reading_list_page.dart';
import 'package:zerotrust_browser/pages/send_tab_sheet.dart';
import 'package:zerotrust_browser/pages/settings_page.dart';
import 'package:zerotrust_browser/pages/site_sheet.dart';
import 'package:zerotrust_browser/pages/start_page.dart';
import 'package:zerotrust_browser/pages/tabs_page.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/qr_sheet.dart';
import 'package:zerotrust_browser/widgets/read_aloud_bar.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';
import 'package:zerotrust_browser/widgets/tab_strip.dart';

/// The browser once unlocked: address bar, the current tab, toolbar.
class BrowserHome extends ConsumerStatefulWidget {
  const BrowserHome({super.key});

  @override
  ConsumerState<BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends ConsumerState<BrowserHome>
    with WidgetsBindingObserver {
  late final BrowserEngine _engine = ref.read(browserEngineProvider);
  final TextEditingController _address = TextEditingController();
  final FocusNode _addressFocus = FocusNode();
  final TextEditingController _findText = TextEditingController();
  StreamSubscription<TabPrompt>? _prompts;

  /// The page being read aloud is in a private tab.
  bool _readingPrivate = false;
  Completer<void>? _systemUi;
  bool _editing = false;
  bool _finding = false;
  String _findResult = '';
  bool _pruned = false;
  bool _voice = false;

  /// What the window was last told about private tabs (B29).
  (bool, bool)? _windowPrivacy;

  /// Pages from other devices already announced (B23).
  final Set<String> _announced = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addressFocus.addListener(() {
      if (!_addressFocus.hasFocus && _editing) setState(() => _editing = false);
    });
    _prompts = ref.read(tabsProvider.notifier).prompts.listen(_onPrompt);
    _engine.pendingLinks.addListener(_openPendingLink);
    _engine.systemUiOpen.addListener(_onSystemUi);
    _engine.readAloud.addListener(_onReadAloud);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    _pushPrivacy(ref.read(browserSettingsProvider));
    _pushMedia(ref.read(browserSettingsProvider));
    await ref
        .read(tabsProvider.notifier)
        .restoreIfEmpty(closeAfterDays: _settings.closeTabsAfterDays);
    // Data of sites from last time that no restored tab shows (B24).
    _tabs.sweepSiteData().ignore();
    // The user's own rules and extra lists (B30), lists weekly.
    ref.read(userBlockRulesProvider).refreshIfDue().ignore();
    await _openPendingLink();
    final bool voice = await _engine.voiceAvailable();
    if (mounted) setState(() => _voice = voice);
    // Weekly, in the background: a fresh signed blocklist.
    ref.read(blocklistUpdaterProvider).checkIfDue().ignore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // What was blocked since the last save, before the app may be closed.
      ref.read(privacyReportRecorderProvider).flush().ignore();
      _tabs.sweepSiteData().ignore();
      // Private tabs need the phone's lock again (B29); not for a file
      // picker or another screen the browser opened itself.
      if (_settings.privateLock &&
          ref.read(tabsProvider).private.isNotEmpty &&
          !_engine.systemUiOpen.value) {
        ref.read(privateLockProvider.notifier).lock();
        // A private page read aloud would go on past the lock.
        if (_readingPrivate && _engine.readAloud.value.active) {
          _engine.readAloudStop().ignore();
        }
      }
    }
    if (state != AppLifecycleState.resumed) return;
    final int? days = _settings.closeTabsAfterDays;
    if (days != null) _tabs.closeUnused(days).ignore();
    ref.read(blocklistUpdaterProvider).checkIfDue().ignore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prompts?.cancel();
    _engine.pendingLinks.removeListener(_openPendingLink);
    _engine.systemUiOpen.removeListener(_onSystemUi);
    _engine.readAloud.removeListener(_onReadAloud);
    _systemUi?.complete();
    _address.dispose();
    _addressFocus.dispose();
    _findText.dispose();
    super.dispose();
  }

  TabsController get _tabs => ref.read(tabsProvider.notifier);
  BrowserSettings get _settings => ref.read(browserSettingsProvider);
  AppL10n get l => context.l10n;

  /// [url] without tracking tags, for copying and sharing.
  String _clean(String url) => shareableUrl(url, _settings);

  void _pushPrivacy(BrowserSettings s) {
    applySettings(_engine, s).ignore();
  }

  /// Background play and the media notification's texts (B26, B27).
  void _pushMedia(BrowserSettings s) {
    final AppL10n l = this.l;
    _engine
        .setMedia(
          backgroundPlay: s.backgroundPlay,
          labels: <String, String>{
            'channel': l.mediaChannel,
            'privateTab': l.privateTab,
            'readingAloud': l.readingAloud,
            'play': l.play,
            'pause': l.pause,
            'stop': l.stop,
          },
        )
        .ignore();
  }

  /// Screenshots and the recent apps preview while private tabs are open
  /// (B29); only sent when it changes.
  void _updateWindowPrivacy(BrowserSettings s, TabsState tabs) {
    final bool secure =
        s.privateNoScreenshots && (tabs.current?.private ?? false);
    final bool hide = s.privateHideRecents && tabs.private.isNotEmpty;
    if (_windowPrivacy == (secure, hide)) return;
    _windowPrivacy = (secure, hide);
    _engine.setWindowPrivacy(secure: secure, hideRecents: hide).ignore();
  }

  void _onReadAloud() {
    final ReadAloudState st = _engine.readAloud.value;
    if (!mounted) return;
    if (st.error == 'noVoice') {
      _snack(l.readAloudNoVoice);
    } else if (st.error == 'failed') {
      _snack(l.readAloudFailed);
    }
    setState(() {});
  }

  /// Pages other devices sent here: announced once each (B23).
  void _announceSent(List<SentTab> sent) {
    for (final SentTab t in sent) {
      if (!_announced.add(t.id)) continue;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.sentFromSnack(t.fromName, t.title)),
          // Flutter keeps a snackbar with an action open until it is tapped.
          persist: false,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l.open,
            onPressed: () async {
              await ref.read(browserDataProvider).dismissSentTab(t.id);
              await _tabs.open(url: t.url);
            },
          ),
        ),
      );
    }
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

  /// A tap on the home screen search bar widget.
  Future<void> _openWidgetAction() async {
    final String? action = await _engine.consumeWidgetAction();
    if (action == null || !mounted) return;
    // A fullscreen video sits over the whole window, above Flutter.
    await _engine.exitFullscreen();
    if (!mounted) return;
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    switch (action) {
      case 'voice':
        final String? text = await _engine.voiceSearch();
        if (text == null || text.trim().isEmpty || !mounted) return;
        await _tabs.open(url: addressOrSearch(text.trim(), _settings.engine));
      case 'qr':
        await _tabs.open();
        await _scanQr();
      case 'private':
        _startEditing(await _tabs.open(private: true));
      default:
        _startEditing(await _tabs.open());
    }
  }

  /// A link or text from another app opens in a new tab.
  Future<void> _openPendingLink() async {
    await _openWidgetAction();
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
              ? l.downloadStarted(e.get<String>('name') ?? l.fileFallbackName)
              : l.cantDownload,
        );
      case 'downloadDone':
        if (e.get<bool>('ok') == true) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  l.savedToDownloads(
                    e.get<String>('name') ?? l.fileFallbackName,
                  ),
                ),
                // Flutter keeps a snackbar with an action open until it is tapped.
                persist: false,
                action: SnackBarAction(
                  label: l.show,
                  onPressed: () => _push(const DownloadsPage()),
                ),
              ),
            );
        } else {
          _snack(l.couldntSave(e.get<String>('name') ?? l.fileFallbackName));
        }
      case 'permission':
        await _askPermission(e);
      case 'httpsFailed':
        await _offerInsecure(e.get<String>('url') ?? '', tab);
      case 'sslError':
        _snack(l.badCertificate);
      case 'find':
        final int count = e.get<int>('count') ?? 0;
        final int active = e.get<int>('active') ?? 0;
        setState(
          () => _findResult = count == 0
              ? (_findText.text.isEmpty ? '' : l.findNoMatches)
              : l.findCount(active + 1, count),
        );
    }
  }

  Future<void> _linkMenu(String? link, String? image, BrowserTab? tab) async {
    final String? target = link ?? image;
    if (target == null) return;
    final bool private = tab?.private ?? false;
    final String? phone = phoneFromTel(link);
    final Set<String> apps = phone == null ? const <String>{} : await _ztApps();
    if (!mounted) return;
    final bool web =
        link != null &&
        (link.startsWith('https://') || link.startsWith('http://'));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: AddressText(
                target,
                maxLines: 2,
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
            ),
            if (phone != null && apps.contains(ZtApps.phone))
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text(l.callWithZtPhone),
                onTap: () {
                  Navigator.pop(sheet);
                  _toApp(ZtApps.phone, 'dial', phone: phone);
                },
              ),
            if (phone != null && apps.contains(ZtApps.contacts))
              ListTile(
                leading: const Icon(Icons.person_add_alt_outlined),
                title: Text(l.saveToZtContacts),
                onTap: () {
                  Navigator.pop(sheet);
                  _toApp(ZtApps.contacts, 'contact', phone: phone);
                },
              ),
            if (link != null && web && !private)
              ListTile(
                leading: const Icon(Icons.tab_outlined),
                title: Text(l.openInNewTab),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: link);
                },
              ),
            if (link != null && web)
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(l.openInPrivateTab),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: link, private: true);
                },
              ),
            if (link != null && web && !private)
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(l.sendLinkToDevice),
                onTap: () {
                  Navigator.pop(sheet);
                  showSendTabSheet(
                    context,
                    ref,
                    url: _clean(link),
                    title: _clean(link),
                  );
                },
              ),
            if (image != null)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(l.openImageInNewTab),
                onTap: () {
                  Navigator.pop(sheet);
                  _tabs.open(url: image, private: private);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(link != null ? l.copyLink : l.copyImageAddress),
              onTap: () {
                Navigator.pop(sheet);
                Clipboard.setData(ClipboardData(text: _clean(target)));
                _snack(l.copied);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(l.share),
              onTap: () {
                Navigator.pop(sheet);
                SharePlus.instance.share(
                  ShareParams(uri: Uri.tryParse(_clean(target))),
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
    final String? phone = phoneFromTel(url);
    if (phone != null) {
      final Set<String> apps = await _ztApps();
      if (!mounted) return;
      if (apps.contains(ZtApps.phone) || apps.contains(ZtApps.contacts)) {
        await _telChoice(url, phone, apps);
        return;
      }
    }
    final bool ok =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            title: Text(l.openInAnotherAppTitle),
            content: Text(switch (scheme) {
              'mailto' => l.externalMail,
              'tel' => l.externalTel,
              _ => l.externalOther,
            }),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(l.stayHere),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(l.open),
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

  /// A phone number on a page, with ZT Phone or ZT Contacts installed:
  /// call it, save it, or use the phone's usual app (B25).
  Future<void> _telChoice(String url, String phone, Set<String> apps) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                phone,
                textDirection: TextDirection.ltr,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            if (apps.contains(ZtApps.phone))
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text(l.callWithZtPhone),
                onTap: () => Navigator.pop(sheet, 'call'),
              ),
            if (apps.contains(ZtApps.contacts))
              ListTile(
                leading: const Icon(Icons.person_add_alt_outlined),
                title: Text(l.saveToZtContacts),
                onTap: () => Navigator.pop(sheet, 'contact'),
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(l.openWithOtherApp),
              onTap: () => Navigator.pop(sheet, 'other'),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l.copyNumber),
              onTap: () => Navigator.pop(sheet, 'copy'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'call':
        await _toApp(ZtApps.phone, 'dial', phone: phone);
      case 'contact':
        await _toApp(ZtApps.contacts, 'contact', phone: phone);
      case 'other':
        await _engine.openExternal(url);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: phone));
        _snack(l.copied);
    }
  }

  // ---- The other ZT apps (B25) ------------------------------------------

  Future<Set<String>> _ztApps() async {
    ref.invalidate(installedZtAppsProvider);
    try {
      return await ref.read(installedZtAppsProvider.future);
    } on Object {
      return const <String>{};
    }
  }

  Future<void> _toApp(
    String package,
    String action, {
    String? text,
    String? subject,
    String? phone,
  }) async {
    final bool ok = await _engine.sendToApp(
      package: package,
      action: action,
      text: text,
      subject: subject,
      phone: phone,
    );
    if (!ok && mounted) _snack(l.appCouldntOpen);
  }

  /// The selected text (or the page's title and address) to ZT Notes.
  Future<void> _saveToNotes(BrowserTab tab) async {
    final String? selection = await _engine.selection(tab.id);
    await _toApp(
      ZtApps.notes,
      'send',
      subject: tab.label,
      text: noteText(
        title: tab.label,
        url: _clean(tab.url!),
        selection: selection,
      ),
    );
  }

  /// "Read later" as a task in ZT Tasks: the page's title, with its address.
  Future<void> _readLaterInTasks(BrowserTab tab) async {
    await _toApp(
      ZtApps.tasks,
      'send',
      subject: tab.label,
      text: '${tab.label}\n${_clean(tab.url!)}',
    );
  }

  // ---- Read aloud (B27) -----------------------------------------------------

  Future<void> _readAloud(BrowserTab tab) async {
    final Article? a = Article.fromJson(await _engine.article(tab.id));
    if (!mounted) return;
    if (a == null) {
      _snack(tab.javascript ? l.readAloudCant : l.readerNeedsJs);
      return;
    }
    final List<String> parts = speechParts(a.content, title: a.title);
    if (parts.isEmpty) {
      _snack(l.readAloudCant);
      return;
    }
    await _engine.readAloudStart(
      parts: parts,
      title: a.title.isNotEmpty ? a.title : tab.label,
      language: a.lang,
      rate: _settings.readAloudRate,
      private: tab.private,
    );
    _readingPrivate = tab.private;
  }

  Future<void> _offerInsecure(String url, BrowserTab? tab) async {
    if (tab == null) return;
    final String host = hostOf(url);
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext d) => AlertDialog(
            icon: const Icon(Icons.no_encryption_gmailerrorred_outlined),
            title: Text(l.notSecureTitle),
            content: Text(l.notSecureBody(host)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(l.continueAnyway),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(l.goBack),
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

  // ---- Site permissions -----------------------------------------------------

  Future<void> _askPermission(TabEvent e) async {
    final int id = e.get<int>('requestId') ?? 0;
    final String origin = e.get<String>('origin') ?? '';
    final String host = (Uri.tryParse(origin)?.host ?? '').isEmpty
        ? origin
        : Uri.parse(origin).host;
    final List<String> kinds = <String>[
      for (final Object? k in (e.data['kinds'] as List<Object?>? ?? const []))
        if (k is String) k,
    ];
    final bool private = e.get<bool>('private') ?? false;
    final PermissionDecision d = decidePermission(
      _settings,
      host,
      kinds,
      private: private,
    );
    if (d.ask.isEmpty) {
      await _engine.answerPermission(id, d.allowed);
      return;
    }
    final String? choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext c) => AlertDialog(
        icon: Icon(
          kinds.contains(SitePermission.location)
              ? Icons.location_on_outlined
              : kinds.contains(SitePermission.camera)
              ? Icons.videocam_outlined
              : Icons.mic_none,
        ),
        title: Text(l.permissionAsk(host, l.permissionPhrase(d.ask))),
        content: Text(
          private ? l.permissionPrivateNote : l.permissionChangeLater,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c, 'block'),
            child: Text(l.block),
          ),
          if (!private)
            TextButton(
              onPressed: () => Navigator.pop(c, 'once'),
              child: Text(l.onlyThisTime),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(c, private ? 'once' : 'allow'),
            child: Text(l.allow),
          ),
        ],
      ),
    );
    final bool allow = choice == 'allow' || choice == 'once';
    if (!private && (choice == 'allow' || choice == 'block')) {
      BrowserSettings next = _settings;
      for (final String kind in d.ask) {
        next = next.withPermission(host, kind, choice == 'allow');
      }
      await ref.read(browserDataProvider).saveSettings(next);
    }
    await _engine.answerPermission(id, <String>{
      ...d.allowed,
      if (allow) ...d.ask,
    });
  }

  // ---- Reader, reading list, page tools ------------------------------------

  Future<void> _toggleReader(BrowserTab tab) async {
    if (tab.reader) {
      await _engine.back(tab.id);
      return;
    }
    final Article? a = Article.fromJson(await _engine.article(tab.id));
    if (!mounted) return;
    if (a == null) {
      _snack(tab.javascript ? l.readerCant : l.readerNeedsJs);
      return;
    }
    await _engine.loadHtml(
      tab.id,
      readerHtml(a, url: tab.url!, savedLabel: l.savedCopy),
      baseUrl: tab.url!,
    );
  }

  Future<void> _addToReadingList(BrowserTab tab) async {
    final String url = tab.url!;
    final Article? a = Article.fromJson(await _engine.article(tab.id));
    try {
      await ref
          .read(browserDataProvider)
          .addToReadingList(
            url,
            a?.title.isNotEmpty == true ? a!.title : tab.label,
            html: a == null
                ? null
                : readerHtml(a, url: url, saved: true, savedLabel: l.savedCopy),
            excerpt: a?.excerpt,
          );
      _snack(a == null ? l.addedToReadingList : l.addedToReadingListOffline);
    } on Object {
      _snack(l.couldntAddReading);
    }
  }

  Future<void> _openReading(ReadingItem item, {required bool saved}) async {
    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    if (!saved || item.saved == null) {
      _openFromList(item.url, newTab: true);
      return;
    }
    try {
      final String? html = await ref.read(browserDataProvider).readSaved(item);
      if (html == null) throw StateError('no copy');
      await _tabs.openHtml(html, item.url);
    } on Object {
      _snack(l.savedCopyUnavailable);
      _openFromList(item.url, newTab: true);
    }
  }

  Future<void> _addShortcut(BrowserTab tab) async {
    final bool ok = await _engine.addShortcut(tab.url!, tab.label, tab.favicon);
    if (!ok) _snack(l.noHomeShortcuts);
  }

  /// The fire button: close every tab and clear browsing data.
  Future<void> _fire() async {
    final List<(String, Duration?)> ranges = <(String, Duration?)>[
      (l.rangeLastHour, const Duration(hours: 1)),
      (l.rangeLast24, const Duration(days: 1)),
      (l.rangeAll, null),
    ];
    int range = 0;
    bool history = true;
    final bool go =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => StatefulBuilder(
            builder: (BuildContext c, StateSetter set) => AlertDialog(
              icon: const Icon(Icons.local_fire_department_outlined),
              title: Text(l.fireTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(l.fireBody),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: history,
                      onChanged: (bool? v) => set(() => history = v ?? true),
                      title: Text(l.fireAlsoHistory),
                    ),
                    if (history)
                      RadioGroup<int>(
                        groupValue: range,
                        onChanged: (int? v) => set(() => range = v ?? 0),
                        child: Column(
                          children: <Widget>[
                            for (int i = 0; i < ranges.length; i++)
                              RadioListTile<int>(
                                contentPadding: EdgeInsets.zero,
                                value: i,
                                title: Text(ranges[i].$1),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(l.clear),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!go) return;
    await _tabs.closeAllForFire();
    await _engine.clearBrowsingData();
    if (history) {
      final Duration? d = ranges[range].$2;
      final BrowserData data = ref.read(browserDataProvider);
      if (d == null) {
        await data.clearHistory();
      } else {
        await data.clearHistorySince(DateTime.now().subtract(d));
      }
      // The report names the sites visited, like history does.
      await ref.read(privacyReportRecorderProvider).clear();
    }
    if (mounted) _snack(l.fireDone);
  }

  Future<void> _scanQr() async {
    final String? text = await _engine.scanQr(prompt: l.qrPrompt);
    if (text == null || text.trim().isEmpty || !mounted) return;
    // Shown in the address bar first: a code can hold any address.
    _address.text = text.trim();
    _address.selection = TextSelection.collapsed(offset: _address.text.length);
    setState(() => _editing = true);
    _addressFocus.requestFocus();
  }

  Future<void> _voiceSearch() async {
    final String? text = await _engine.voiceSearch(prompt: l.voicePrompt);
    if (text == null || text.trim().isEmpty || !mounted) return;
    await go(text.trim());
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
    final bool pinned = onPage && _settings.isPinned(tab.url!);
    final Set<String> apps = onPage ? await _ztApps() : const <String>{};
    if (!mounted) return;
    final bool reading = _engine.readAloud.value.active;
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
                          tooltip: l.forward,
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: tab.canGoForward
                              ? () => run(() => _engine.forward(tab.id))
                              : null,
                        ),
                        IconButton(
                          tooltip: saved == null
                              ? l.bookmarkAction
                              : l.removeBookmark,
                          icon: Icon(
                            saved == null ? Icons.star_border : Icons.star,
                          ),
                          onPressed: () => run(() async {
                            if (saved == null) {
                              await data.addBookmark(tab.url!, tab.label);
                              _snack(l.bookmarked);
                            } else {
                              await data.removeBookmark(saved.id);
                              _snack(l.bookmarkRemoved);
                            }
                          }),
                        ),
                        IconButton(
                          tooltip: l.share,
                          icon: const Icon(Icons.share_outlined),
                          onPressed: () => run(
                            () => SharePlus.instance.share(
                              ShareParams(
                                uri: Uri.parse(_clean(tab.url!)),
                                subject: tab.label,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l.reload,
                          icon: const Icon(Icons.refresh),
                          onPressed: () => run(() => _engine.reload(tab.id)),
                        ),
                      ],
                    ),
                  ),
                if (onPage) const Divider(),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l.newTab),
                  onTap: () => run(() => _tabs.open()),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l.newPrivateTab),
                  onTap: () => run(() => _tabs.open(private: true)),
                ),
                ListTile(
                  leading: const Icon(Icons.bookmarks_outlined),
                  title: Text(l.bookmarks),
                  onTap: () =>
                      run(() => _push(BookmarksPage(onOpen: _openFromList))),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(l.history),
                  onTap: () =>
                      run(() => _push(HistoryPage(onOpen: _openFromList))),
                ),
                ListTile(
                  leading: const Icon(Icons.chrome_reader_mode_outlined),
                  title: Text(l.readingList),
                  onTap: () =>
                      run(() => _push(ReadingListPage(onOpen: _openReading))),
                ),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(l.downloads),
                  onTap: () => run(() => _push(const DownloadsPage())),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l.privacyReport),
                  onTap: () => run(() => _push(const PrivacyReportPage())),
                ),
                if (onPage) const Divider(),
                if (onPage)
                  ListTile(
                    leading: Icon(
                      tab.reader
                          ? Icons.web_outlined
                          : Icons.chrome_reader_mode_outlined,
                    ),
                    title: Text(tab.reader ? l.leaveReader : l.readerView),
                    onTap: () => run(() => _toggleReader(tab)),
                  ),
                if (onPage)
                  ListTile(
                    leading: const Icon(Icons.bookmark_add_outlined),
                    title: Text(
                      data.readingFor(tab.url!) == null
                          ? l.addToReadingList
                          : l.saveAgainReadingList,
                    ),
                    onTap: () => run(() => _addToReadingList(tab)),
                  ),
                if (onPage)
                  ListTile(
                    leading: Icon(
                      reading
                          ? Icons.voice_over_off_outlined
                          : Icons.record_voice_over_outlined,
                    ),
                    title: Text(reading ? l.stopReadingAloud : l.readAloud),
                    onTap: () => run(
                      () => reading ? _engine.readAloudStop() : _readAloud(tab),
                    ),
                  ),
                if (onPage && !tab.private)
                  ListTile(
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(l.sendToDevice),
                    onTap: () => run(
                      () => showSendTabSheet(
                        context,
                        ref,
                        url: _clean(tab.url!),
                        title: tab.label,
                      ),
                    ),
                  ),
                if (onPage && apps.contains(ZtApps.notes))
                  ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(l.saveToZtNotes),
                    subtitle: Text(l.saveToZtNotesSub),
                    onTap: () => run(() => _saveToNotes(tab)),
                  ),
                if (onPage && apps.contains(ZtApps.tasks))
                  ListTile(
                    leading: const Icon(Icons.task_alt),
                    title: Text(l.readLaterInZtTasks),
                    onTap: () => run(() => _readLaterInTasks(tab)),
                  ),
                if (onPage)
                  ListTile(
                    leading: const Icon(Icons.find_in_page_outlined),
                    title: Text(l.findInPage),
                    onTap: () => run(_openFind),
                  ),
                if (onPage)
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: Text(l.printOrPdf),
                    onTap: () =>
                        run(() => _engine.printPage(tab.id, tab.label)),
                  ),
                if (onPage)
                  ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(l.shareAsQr),
                    onTap: () => run(
                      () => showQrSheet(context, _clean(tab.url!), tab.label),
                    ),
                  ),
                if (onPage && !tab.private)
                  ListTile(
                    leading: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    title: Text(pinned ? l.unpinFromStart : l.pinToStart),
                    onTap: () => run(() async {
                      final BrowserSettings s = _settings;
                      await data.saveSettings(
                        pinned
                            ? s.withoutShortcut(tab.url!)
                            : s.withShortcut(tab.url!, tab.label),
                      );
                      if (mounted) {
                        _snack(pinned ? l.unpinnedFromStart : l.pinnedToStart);
                      }
                    }),
                  ),
                if (onPage && !tab.private)
                  ListTile(
                    leading: const Icon(Icons.add_to_home_screen),
                    title: Text(l.addToHomeScreen),
                    onTap: () => run(() => _addShortcut(tab)),
                  ),
                if (onPage)
                  SwitchListTile(
                    secondary: const Icon(Icons.desktop_windows_outlined),
                    title: Text(l.desktopSite),
                    value: tab.desktop,
                    onChanged: (bool v) =>
                        run(() => _tabs.setDesktop(tab.id, v)),
                  ),
                ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(l.fireMenu),
                  onTap: () => run(_fire),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l.settings),
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
    ref.listen(browserSettingsProvider, (
      BrowserSettings? prev,
      BrowserSettings next,
    ) {
      _pushPrivacy(next);
      if (prev?.backgroundPlay != next.backgroundPlay) _pushMedia(next);
      // Rules changed here or on another device (B30).
      if (prev == null ||
          !_same(prev.blockedHosts, next.blockedHosts) ||
          !_same(prev.unblockedHosts, next.unblockedHosts) ||
          !_same(prev.filterLists, next.filterLists)) {
        ref.read(userBlockRulesProvider).refreshIfDue().ignore();
      }
    });
    // Pages other devices sent here (B23).
    ref.listen(sentToMeProvider, (_, AsyncValue<List<SentTab>> next) {
      final List<SentTab>? sent = next.value;
      if (sent != null && sent.isNotEmpty) _announceSent(sent);
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
    final BrowserSettings settings = ref.watch(browserSettingsProvider);
    final BrowserTab? tab = tabs.current;
    final bool private = tab?.private ?? false;
    final ThemeData base = Theme.of(context);
    final ThemeData theme = private ? _privateTheme(base) : base;
    // Tablets and unfolded foldables get a tab strip (B31).
    final bool wide = MediaQuery.sizeOf(context).width >= 720;
    final ReadAloudState reading = _engine.readAloud.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateWindowPrivacy(settings, tabs);
    });

    final Widget addressBar = _AddressBar(
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
      onReader:
          tab != null && !tab.isStartPage && (tab.readerable || tab.reader)
          ? () => _toggleReader(tab)
          : null,
      onVoice: _voice ? _voiceSearch : null,
      onScan: _scanQr,
      engines: settings.engines,
    );

    // Locked private tabs (B29): nothing of the page shows, and none of its
    // actions (menu, read aloud, reading list...) work until unlocked.
    if (private && ref.watch(privateLockProvider)) {
      return Theme(
        data: theme,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? _) {
            if (!didPop) _onBack(null);
          },
          child: Scaffold(body: SafeArea(child: _privateLocked())),
        ),
      );
    }

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
                if (wide)
                  TabStrip(
                    tabs: private ? tabs.private : tabs.normal,
                    currentId: tab?.id,
                    onSelect: _tabs.select,
                    onClose: (String id) => _tabs.close(id),
                    onNew: () => _tabs.open(private: private),
                    onOverview: () => _push(TabsPage(startPrivate: private)),
                  ),
                if (wide)
                  _WideBar(
                    tab: tab,
                    addressBar: addressBar,
                    onBack: tab != null && tab.canGoBack && !tab.isStartPage
                        ? () => _engine.back(tab.id)
                        : null,
                    onForward: tab != null && tab.canGoForward
                        ? () => _engine.forward(tab.id)
                        : null,
                    onReload: tab == null || tab.isStartPage
                        ? null
                        : () => tab.loading
                              ? _engine.stop(tab.id)
                              : _engine.reload(tab.id),
                    onHome: () => go(_settings.engine.home),
                    onMenu: () => _menu(tab),
                  )
                else
                  addressBar,
                if (tab != null && tab.loading && !_editing)
                  LinearProgressIndicator(
                    value: tab.progress <= 0 ? null : tab.progress / 100,
                    minHeight: 2,
                  )
                else
                  const SizedBox(height: 2),
                Expanded(child: _content(tab)),
                if (_finding && tab != null) _findBar(tab),
                if (reading.active) ReadAloudBar(state: reading),
                if (!wide)
                  _Toolbar(
                    tab: tab,
                    tabCount: private
                        ? tabs.private.length
                        : tabs.normal.length,
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

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Private tabs behind the phone's lock (B29).
  Widget _privateLocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(l.privateLocked, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref
                  .read(privateLockProvider.notifier)
                  .unlock(l.privateUnlockReason),
              icon: const Icon(Icons.lock_open),
              label: Text(l.unlock),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _push(const TabsPage()),
              child: Text(l.tabs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BrowserTab? tab) {
    if (_editing) {
      return Suggestions(
        controller: _address,
        private: tab?.private ?? false,
        onOpen: (String url) => go(url),
      );
    }
    if (tab == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _tabs.open(),
          icon: const Icon(Icons.add),
          label: Text(l.newTab),
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
              Text(l.pageStopped, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _tabs.revive(tab.id),
                child: Text(l.reload),
              ),
            ],
          ),
        ),
      );
    }
    if (tab.unloaded) {
      // Loads again when shown (tabs restored after a restart, or unloaded
      // to save memory).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BrowserTab? now = ref.read(tabsProvider).current;
        if (now != null && now.id == tab.id && now.unloaded) {
          _tabs.select(tab.id);
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    if (tab.private && ref.watch(privateLockProvider)) return _privateLocked();
    if (tab.isStartPage) {
      return StartPage(
        private: tab.private,
        onOpen: (String url) => go(url),
        onSearch: () => _startEditing(tab),
        onReport: () => _push(const PrivacyReportPage()),
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
                decoration: InputDecoration(
                  hintText: l.findInPage,
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (String t) => _engine.find(tab.id, t),
                onSubmitted: (_) => _engine.findNext(tab.id),
              ),
            ),
            Text(_findResult, style: Theme.of(context).textTheme.bodySmall),
            IconButton(
              tooltip: l.previous,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () => _engine.findNext(tab.id, forward: false),
            ),
            IconButton(
              tooltip: l.next,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () => _engine.findNext(tab.id),
            ),
            IconButton(
              tooltip: l.close,
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
    required this.onReader,
    required this.onVoice,
    required this.onScan,
    required this.engines,
  });

  /// To show the search words instead of a search page's address.
  final List<SearchEngine> engines;
  final BrowserTab? tab;
  final bool editing;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback? onShield;

  /// Reader view (shown when the page is an article).
  final VoidCallback? onReader;
  final VoidCallback? onVoice;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BrowserTab? t = tab;
    final bool private = t?.private ?? false;
    final bool showsAddress = t != null && !t.isStartPage;
    final Widget leading;
    if (editing) {
      leading = IconButton(
        tooltip: l.cancel,
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
        tooltip: l.siteProtection,
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
                        decoration: InputDecoration(
                          hintText: l.addressHint,
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: onSubmit,
                      )
                    : InkWell(
                        onTap: onTap,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            showsAddress
                                ? displayAddress(t.url, engines)
                                : (private
                                      ? l.addressHintPrivate
                                      : l.addressHint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // An address reads left to right in Hebrew too.
                            textDirection: showsAddress
                                ? TextDirection.ltr
                                : null,
                            style: TextStyle(
                              color: showsAddress
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
              ),
              if (editing)
                ListenableBuilder(
                  listenable: controller,
                  builder: (BuildContext context, _) => controller.text.isEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (onVoice != null)
                              IconButton(
                                tooltip: l.voiceSearch,
                                icon: const Icon(Icons.mic_none),
                                onPressed: onVoice,
                              ),
                            IconButton(
                              tooltip: l.scanQr,
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: onScan,
                            ),
                          ],
                        )
                      : IconButton(
                          tooltip: l.clear,
                          icon: const Icon(Icons.close),
                          onPressed: controller.clear,
                        ),
                )
              else if (onReader != null)
                IconButton(
                  tooltip: t?.reader == true ? l.leaveReader : l.readerView,
                  isSelected: t?.reader == true,
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  selectedIcon: const Icon(Icons.chrome_reader_mode),
                  onPressed: onReader,
                )
              else if (private)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Tooltip(
                    message: l.privateTooltip,
                    child: const Icon(Icons.visibility_off_outlined),
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

/// The navigation row on wide screens (B31): back, forward, reload and home
/// beside the address bar, the menu at the end; no bottom toolbar.
class _WideBar extends StatelessWidget {
  const _WideBar({
    required this.tab,
    required this.addressBar,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onMenu,
  });

  final BrowserTab? tab;
  final Widget addressBar;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onReload;
  final VoidCallback onHome;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final bool loading = tab?.loading ?? false;
    return Row(
      children: <Widget>[
        const SizedBox(width: 4),
        IconButton(
          tooltip: l.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        IconButton(
          tooltip: l.forward,
          icon: const Icon(Icons.arrow_forward),
          onPressed: onForward,
        ),
        IconButton(
          tooltip: loading ? l.stop : l.reload,
          icon: Icon(loading ? Icons.close : Icons.refresh),
          onPressed: onReload,
        ),
        IconButton(
          tooltip: l.home,
          icon: const Icon(Icons.home_outlined),
          onPressed: onHome,
        ),
        Expanded(child: addressBar),
        IconButton(
          tooltip: l.menu,
          icon: const Icon(Icons.more_vert),
          onPressed: onMenu,
        ),
        const SizedBox(width: 4),
      ],
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
    final AppL10n l = context.l10n;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            IconButton(
              tooltip: l.back,
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            ),
            IconButton(
              tooltip: l.home,
              icon: const Icon(Icons.home_outlined),
              onPressed: onHome,
            ),
            IconButton(
              tooltip: l.newTab,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onNewTab,
            ),
            IconButton(
              tooltip: l.tabs,
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
              tooltip: l.menu,
              icon: const Icon(Icons.more_vert),
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the address bar offers while typing: a search for the words,
/// the search engine's suggestions (when turned on), then matching
/// bookmarks and history.
class Suggestions extends ConsumerStatefulWidget {
  const Suggestions({
    super.key,
    required this.controller,
    required this.onOpen,
    this.private = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onOpen;

  /// Typing in a private tab is never sent to the search engine.
  final bool private;

  @override
  ConsumerState<Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<Suggestions> {
  Timer? _debounce;
  List<String> _remote = const <String>[];

  /// What [_remote] answers, so stale answers are dropped.
  String _remoteFor = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_typed);
    _typed();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_typed);
    _debounce?.cancel();
    super.dispose();
  }

  void _typed() {
    _debounce?.cancel();
    final BrowserSettings s = ref.read(browserSettingsProvider);
    final String text = widget.controller.text.trim();
    if (widget.private ||
        !s.searchSuggestions ||
        s.engine.suggest == null ||
        !SearchSuggestions.shouldAsk(text)) {
      if (_remote.isNotEmpty) setState(() => _remote = const <String>[]);
      _remoteFor = '';
      return;
    }
    if (text == _remoteFor) return;
    // Wait for a pause in typing: fewer requests, fewer half-words sent.
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final List<String> got = await ref
          .read(searchSuggestionsProvider)
          .fetch(s.engine, text);
      if (!mounted || widget.controller.text.trim() != text) return;
      setState(() {
        _remote = got;
        _remoteFor = text;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final TextEditingController controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, _) {
        final String typed = controller.text.trim();
        final String q = typed.toLowerCase();
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
        final BrowserSettings s = ref.watch(browserSettingsProvider);
        final SearchEngine engine = s.engine;
        final List<String> remote = <String>[
          for (final String r in _remote)
            if (r.toLowerCase() != q) r,
        ];
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: <Widget>[
            if (q.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(typed),
                subtitle: Text(l.searchWith(engine.name)),
                onTap: () => widget.onOpen(engine.searchUrl(typed).toString()),
              ),
            for (final String r in remote)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: l.editThisSearch,
                  icon: const Icon(Icons.north_west, size: 18),
                  onPressed: () {
                    controller.text = '$r ';
                    controller.selection = TextSelection.collapsed(
                      offset: controller.text.length,
                    );
                  },
                ),
                onTap: () => widget.onOpen(engine.searchUrl(r).toString()),
              ),
            for (final Bookmark x in b)
              ListTile(
                leading: SiteIcon(url: x.url, size: 28),
                title: Text(
                  x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: AddressText(displayAddress(x.url, s.engines)),
                trailing: const Icon(Icons.star, size: 18),
                onTap: () => widget.onOpen(x.url),
              ),
            for (final HistoryEntry x in h)
              ListTile(
                leading: SiteIcon(url: x.url, size: 28),
                title: Text(
                  x.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: AddressText(displayAddress(x.url, s.engines)),
                trailing: const Icon(Icons.history, size: 18),
                onTap: () => widget.onOpen(x.url),
              ),
          ],
        );
      },
    );
  }
}
