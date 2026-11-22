import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/clean_url.dart';

/// Something a tab's page did: new state, a favicon, a link to open...
class TabEvent {
  const TabEvent(this.tabId, this.type, this.data);

  final String tabId;

  /// state, favicon, visited, openTab, contextMenu, external, download,
  /// downloadDone, httpsFailed, sslError, find, crashed, unloaded,
  /// permission.
  final String type;
  final Map<Object?, Object?> data;

  T? get<T>(String key) => data[key] as T?;
}

/// The Android web engine behind the `zt_browser/engine` channel (see
/// MainActivity.kt). Each tab is a native WebView that lives until
/// [closeTab], whether or not it is on screen.
class BrowserEngine {
  BrowserEngine([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('zt_browser/engine') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast();

  /// Set when another app hands over a link while ZT Browser is open.
  final ValueNotifier<int> pendingLinks = ValueNotifier<int>(0);

  /// True while a system picker (file upload) is open, so auto-lock waits.
  final ValueNotifier<bool> systemUiOpen = ValueNotifier<bool>(false);

  Stream<TabEvent> get events => _events.stream;

  /// Where read aloud is: idle, speaking or paused, and which part.
  final ValueNotifier<ReadAloudState> readAloud = ValueNotifier<ReadAloudState>(
    const ReadAloudState(),
  );

  /// The app left the screen (home, recent apps, another app on top).
  final StreamController<void> appHidden = StreamController<void>.broadcast();

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'tabEvent':
        final Map<Object?, Object?> data =
            (call.arguments as Map<Object?, Object?>?) ?? const {};
        _events.add(
          TabEvent(data['tabId'] as String, data['type'] as String, data),
        );
      case 'openPending':
        pendingLinks.value++;
      case 'systemUi':
        systemUiOpen.value = call.arguments == true;
      case 'readAloud':
        final Map<Object?, Object?> data =
            (call.arguments as Map<Object?, Object?>?) ?? const {};
        readAloud.value = ReadAloudState.fromMap(data);
      case 'appHidden':
        appHidden.add(null);
      case 'downloadEvent':
        final Map<Object?, Object?> data =
            (call.arguments as Map<Object?, Object?>?) ?? const {};
        _downloadEvents.add(DownloadEvent.fromMap(data));
    }
    return null;
  }

  final StreamController<DownloadEvent> _downloadEvents =
      StreamController<DownloadEvent>.broadcast();

  /// A download finished (done or failed), whichever tab it came from.
  Stream<DownloadEvent> get downloadEvents => _downloadEvents.stream;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // Tests and platforms without the engine.
    }
  }

  /// A link from another app (or shared text), once.
  Future<String?> consumePendingLink() => _call<String>('consumePending');

  /// A tap on the search bar widget, once: 'search', 'voice', 'private'
  /// or 'qr'; or 'downloads' from a download notification.
  Future<String?> consumeWidgetAction() => _call<String>('consumeWidgetAction');

  Future<void> createTab(
    String tabId, {
    required bool private,
    String? url,
    bool desktop = false,
    Map<String, Object?>? identity,
  }) => _call<void>('createTab', <String, Object?>{
    'tabId': tabId,
    'private': private,
    'url': url,
    'desktop': desktop,
    'identity': identity,
  });

  Future<void> closeTab(String tabId) =>
      _call<void>('closeTab', <String, Object?>{'tabId': tabId});

  Future<void> load(String tabId, String url) =>
      _call<void>('load', <String, Object?>{'tabId': tabId, 'url': url});

  Future<void> loadInsecure(String tabId, String url) => _call<void>(
    'loadInsecure',
    <String, Object?>{'tabId': tabId, 'url': url},
  );

  Future<void> back(String tabId) =>
      _call<void>('back', <String, Object?>{'tabId': tabId});
  Future<void> forward(String tabId) =>
      _call<void>('forward', <String, Object?>{'tabId': tabId});
  Future<void> reload(String tabId) =>
      _call<void>('reload', <String, Object?>{'tabId': tabId});
  Future<void> stop(String tabId) =>
      _call<void>('stop', <String, Object?>{'tabId': tabId});
  Future<void> requestState(String tabId) =>
      _call<void>('state', <String, Object?>{'tabId': tabId});

  /// Leaves fullscreen video, which the native side shows above Flutter.
  Future<void> exitFullscreen() => _call<void>('exitFullscreen');

  Future<void> setDesktop(String tabId, bool on) =>
      _call<void>('setDesktop', <String, Object?>{'tabId': tabId, 'on': on});

  // ---- B42: browser identity (user agent) ----

  /// The identity for all sites ([global], null for the default) and for
  /// sites with their own ([rules], host to identity), as
  /// `Identities.config` builds them.
  Future<void> setIdentity({
    required Map<String, Object?>? global,
    required Map<String, Object?> rules,
  }) => _call<void>('setIdentity', <String, Object?>{
    'global': global,
    'rules': rules,
  });

  /// The identity of one tab; null follows the settings again.
  Future<void> setTabIdentity(String tabId, Map<String, Object?>? identity) =>
      _call<void>('setTabIdentity', <String, Object?>{
        'tabId': tabId,
        'identity': identity,
      });

  /// New random identities from now on.
  Future<void> shuffleIdentity() => _call<void>('shuffleIdentity');

  /// The phone's engine version and what the default identity sends.
  Future<Map<Object?, Object?>> identityInfo() async =>
      await _call<Map<Object?, Object?>>('identityInfo') ??
      const <Object?, Object?>{};

  Future<void> find(String tabId, String text) =>
      _call<void>('find', <String, Object?>{'tabId': tabId, 'text': text});
  Future<void> findNext(String tabId, {bool forward = true}) => _call<void>(
    'findNext',
    <String, Object?>{'tabId': tabId, 'forward': forward},
  );
  Future<void> clearFind(String tabId) =>
      _call<void>('clearFind', <String, Object?>{'tabId': tabId});

  Future<void> setPrivacy({
    required bool blockTrackers,
    required bool httpsOnly,
    required List<String> allowedSites,
    bool hideElements = true,
    bool fingerprinting = true,
    List<String> javascriptOff = const <String>[],
    bool stripTracking = true,
    bool safeBrowsing = true,
  }) => _call<void>('setPrivacy', <String, Object?>{
    'stripTracking': stripTracking,
    'safeBrowsing': safeBrowsing,
    // The rules for links tapped on a page: one list, kept in Dart.
    'trackingParams': trackingParams.toList(),
    'trackingPrefixes': trackingPrefixes,
    'redirectWrappers': <Map<String, String>>[
      for (final RedirectWrapper w in redirectWrappers) w.toJson(),
    ],
    'blockTrackers': blockTrackers,
    'httpsOnly': httpsOnly,
    'allowedSites': allowedSites,
    'hideElements': hideElements,
    'fingerprinting': fingerprinting,
    'javascriptOff': javascriptOff,
  });

  /// Page text size (percent), darkening of pages in dark mode and pull
  /// down to reload (B28).
  Future<void> setDisplay({
    required int textZoom,
    required bool darkPages,
    bool pullToRefresh = true,
  }) => _call<void>('setDisplay', <String, Object?>{
    'textZoom': textZoom,
    'darkPages': darkPages,
    'pullToRefresh': pullToRefresh,
  });

  /// The tab now on screen: the engine keeps it, and unloads old ones.
  Future<void> select(String tabId) =>
      _call<void>('select', <String, Object?>{'tabId': tabId});

  /// B-1: the phishing and malware list: its date, how many sites, and
  /// where a downloaded list goes.
  Future<Map<Object?, Object?>> safetyInfo() async =>
      await _call<Map<Object?, Object?>>('safetyInfo') ??
      const <Object?, Object?>{};

  /// Reads the list again after a download.
  Future<void> reloadSafetyList() => _call<void>('reloadSafetyList');

  /// The warning page's texts, in the app's language.
  Future<void> setSafetyLabels(Map<String, String> labels) =>
      _call<void>('safetyLabels', <String, Object?>{'labels': labels});

  /// B-7: the hosts blocked on [tabId]'s page now, with how many requests
  /// each.
  Future<Map<String, int>> blockedHosts(String tabId) async {
    final Map<Object?, Object?>? m = await _call<Map<Object?, Object?>>(
      'blockedHosts',
      <String, Object?>{'tabId': tabId},
    );
    return <String, int>{
      if (m != null)
        for (final MapEntry<Object?, Object?> e in m.entries)
          if (e.key is String && e.value is int)
            e.key! as String: e.value! as int,
    };
  }

  Future<int> blocklistSize() async => await _call<int>('blocklistSize') ?? 0;

  /// size, date (of the list), updated (a downloaded list is in use), file
  /// (where a downloaded list goes).
  Future<Map<Object?, Object?>> blocklistInfo() async =>
      await _call<Map<Object?, Object?>>('blocklistInfo') ??
      const <Object?, Object?>{};

  /// Reads the newest list again, after an update was saved.
  Future<void> reloadBlocklist() => _call<void>('reloadBlocklist');

  /// The user's answer to a site's camera, microphone or location request.
  Future<void> answerPermission(int requestId, Iterable<String> allowed) =>
      _call<void>('answerPermission', <String, Object?>{
        'requestId': requestId,
        'allowed': allowed.toList(),
      });

  /// The page as a Readability article, or null when it isn't one.
  Future<Map<String, Object?>?> article(String tabId) async {
    final String? raw = await _call<String>('article', <String, Object?>{
      'tabId': tabId,
    });
    if (raw == null || raw == 'null') return null;
    try {
      // The engine hands back the script's value as JSON: here, a string
      // holding the article's JSON.
      final Object? outer = jsonDecode(raw);
      final Object? inner = outer is String ? jsonDecode(outer) : outer;
      return inner is Map<String, Object?> ? inner : null;
    } on FormatException {
      return null;
    }
  }

  /// Shows [html] in the tab as if it were [baseUrl] (reader, saved page).
  Future<void> loadHtml(
    String tabId,
    String html, {
    required String baseUrl,
    bool reader = true,
  }) => _call<void>('loadHtml', <String, Object?>{
    'tabId': tabId,
    'html': html,
    'baseUrl': baseUrl,
    'reader': reader,
  });

  Future<List<Map<Object?, Object?>>> downloads() async =>
      (await _call<List<Object?>>('downloads') ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .toList();

  /// Opens a downloaded file in another app: [DownloadResult.done],
  /// [DownloadResult.noApp], [DownloadResult.missing] or
  /// [DownloadResult.failed]. Never throws.
  Future<DownloadResult> openDownload(String key) =>
      _downloadAction('openDownload', key);

  /// The share sheet for a downloaded file.
  Future<DownloadResult> shareDownload(String key) =>
      _downloadAction('shareDownload', key);

  Future<DownloadResult> _downloadAction(String method, String key) async {
    try {
      return DownloadResult.parse(
        await _call<Object>(method, <String, Object?>{'key': key}),
      );
    } on PlatformException {
      return DownloadResult.failed;
    }
  }

  /// The phone's own Downloads folder (the Files app); false when none.
  Future<bool> showDownloadsFolder() async {
    try {
      return await _call<bool>('showDownloadsFolder') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts a download the person said yes to (B35), under [name]. From a
  /// private tab, [keepPrivate] keeps it encrypted in the app until the
  /// private tabs close (B33). Returns its key, or null when the page's
  /// offer has expired.
  Future<String?> startDownload(
    int requestId, {
    required String name,
    bool keepPrivate = true,
    bool openWhenDone = false,
  }) async {
    try {
      return await _call<String>('startDownload', <String, Object?>{
        'requestId': requestId,
        'name': name,
        'keepPrivate': keepPrivate,
        'openWhenDone': openWhenDone,
      });
    } on PlatformException {
      return null;
    }
  }

  /// The person said no: let go of what the page offered.
  Future<void> dismissDownload(int requestId) =>
      _call<void>('dismissDownload', <String, Object?>{'requestId': requestId});

  Future<void> pauseDownload(String key) =>
      _call<void>('pauseDownload', <String, Object?>{'key': key});

  /// Resumes a paused download, or tries a failed one again from where it
  /// stopped.
  Future<void> resumeDownload(String key) =>
      _call<void>('resumeDownload', <String, Object?>{'key': key});

  /// Moves a private download into the phone's Downloads, where it stays.
  Future<bool> saveDownloadToPhone(String key) async {
    try {
      return await _call<bool>('saveDownloadToPhone', <String, Object?>{
            'key': key,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// The download notification's texts in the app's language.
  Future<void> setDownloadLabels(Map<String, String> labels) =>
      _call<void>('downloadLabels', <String, Object?>{'labels': labels});

  Future<void> deleteDownload(String key) async {
    try {
      await _call<void>('deleteDownload', <String, Object?>{'key': key});
    } on PlatformException {
      // Already gone; the list refresh shows what's left.
    }
  }

  /// B36: takes downloads off the list. Files in the phone's storage stay
  /// where they are; private ones, which live only in the app, go.
  Future<void> forgetDownloads(List<String> keys) =>
      _call<void>('forgetDownloads', <String, Object?>{'keys': keys});

  /// B36: renames a finished download; false when it couldn't.
  Future<bool> renameDownload(String key, String name) async {
    try {
      return await _call<bool>('renameDownload', <String, Object?>{
            'key': key,
            'name': name,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// B38: Wi-Fi only, how many at once and auto-delete after N days (0
  /// keeps files).
  Future<void> setDownloadRules({
    required bool wifiOnly,
    required int maxParallel,
    required int autoDeleteDays,
  }) => _call<void>('setDownloadRules', <String, Object?>{
    'wifiOnly': wifiOnly,
    'maxParallel': maxParallel,
    'autoDeleteDays': autoDeleteDays,
  });

  /// B38: the folder downloads are saved to (one the person chose, such as
  /// on an SD card), or null for the phone's Downloads.
  Future<String?> downloadFolder() async {
    try {
      return await _call<String>('downloadFolder');
    } on PlatformException {
      return null;
    }
  }

  /// B38: the system folder picker; the chosen folder's name, or null when
  /// the person backed out.
  Future<String?> pickDownloadFolder() async {
    try {
      return await _call<String>('pickDownloadFolder');
    } on PlatformException {
      return null;
    }
  }

  /// B38: back to the phone's Downloads folder.
  Future<void> clearDownloadFolder() => _call<void>('clearDownloadFolder');

  // ---- B39: the download vault ----------------------------------------

  Future<List<Map<Object?, Object?>>> vaultList() async {
    try {
      return (await _call<List<Object?>>('vaultList') ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .toList();
    } on PlatformException {
      return const <Map<Object?, Object?>>[];
    }
  }

  /// Moves a finished download into the vault (and off the phone).
  Future<bool> vaultAddDownload(String key) =>
      _bool('vaultAddDownload', <String, Object?>{'key': key});

  /// The system file picker; picked files go into the vault. With [move]
  /// the originals are deleted where the phone allows it. Returns how many
  /// were added and how many originals stayed.
  Future<({int added, int kept})> vaultImport({required bool move}) async {
    try {
      final Map<Object?, Object?>? r = await _call<Map<Object?, Object?>>(
        'vaultImport',
        <String, Object?>{'move': move},
      );
      return (
        added: (r?['added'] as num?)?.toInt() ?? 0,
        kept: (r?['kept'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return (added: 0, kept: 0);
    }
  }

  Future<DownloadResult> vaultOpen(String id) => _vaultAction('vaultOpen', id);

  Future<DownloadResult> vaultShare(String id) =>
      _vaultAction('vaultShare', id);

  Future<DownloadResult> _vaultAction(String method, String id) async {
    try {
      return DownloadResult.parse(
        await _call<Object>(method, <String, Object?>{'id': id}),
      );
    } on PlatformException {
      return DownloadResult.failed;
    }
  }

  /// Takes a file out of the vault into the phone's Downloads.
  Future<bool> vaultMoveToPhone(String id) =>
      _bool('vaultMoveToPhone', <String, Object?>{'id': id});

  Future<bool> vaultRename(String id, String name) =>
      _bool('vaultRename', <String, Object?>{'id': id, 'name': name});

  Future<void> vaultDelete(String id) async {
    try {
      await _call<void>('vaultDelete', <String, Object?>{'id': id});
    } on PlatformException {
      // Already gone.
    }
  }

  /// The vault was left or locked: plain copies made to open files go.
  Future<void> vaultClose() async {
    try {
      await _call<void>('vaultClose');
    } on PlatformException {
      // Nothing to clean.
    }
  }

  Future<bool> _bool(String method, Map<String, Object?> args) async {
    try {
      return await _call<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ---- B40: send a download on --------------------------------------

  /// ZT Notes' app id, for "Send to ZT Notes".
  static const String notesPackage = 'dev.sagron.zerotrustnotes';

  /// Hands a finished download straight to [package] (ZT Notes).
  Future<SendResult> sendDownloadTo(String key, String package) => _send(
    'sendDownloadTo',
    <String, Object?>{'key': key, 'package': package},
  );

  /// Hands a file from the vault straight to [package] (ZT Notes).
  Future<SendResult> vaultSendTo(String id, String package) =>
      _send('vaultSendTo', <String, Object?>{'id': id, 'package': package});

  Future<SendResult> _send(String method, Map<String, Object?> args) async {
    try {
      return SendResult.parse(await _call<Object>(method, args));
    } on PlatformException {
      return SendResult.failed;
    }
  }

  /// The bytes of a finished download, or null when it is over [max] bytes
  /// or can't be read.
  Future<Uint8List?> downloadBytes(String key, int max) =>
      _bytes('downloadBytes', <String, Object?>{'key': key, 'max': max});

  /// The bytes of a file in the vault, or null when it is over [max].
  Future<Uint8List?> vaultBytes(String id, int max) =>
      _bytes('vaultBytes', <String, Object?>{'id': id, 'max': max});

  Future<Uint8List?> _bytes(String method, Map<String, Object?> args) async {
    try {
      return await _call<Uint8List>(method, args);
    } on PlatformException {
      return null;
    }
  }

  /// Saves a received file into Downloads (or the picked folder) and lists
  /// it with the downloads.
  Future<bool> saveBytesToDownloads(
    String name,
    String mime,
    Uint8List bytes,
  ) => _bool('saveBytesToDownloads', <String, Object?>{
    'name': name,
    'mime': mime,
    'bytes': bytes,
  });

  /// The system print screen, which can also save the page as a PDF.
  Future<void> printPage(String tabId, String title) =>
      _call<void>('print', <String, Object?>{'tabId': tabId, 'title': title});

  /// Asks the launcher to pin a shortcut; false when it can't.
  Future<bool> addShortcut(String url, String title, Uint8List? icon) async =>
      await _call<bool>('addShortcut', <String, Object?>{
        'url': url,
        'title': title,
        'icon': icon,
      }) ??
      false;

  /// A file the user picks, or null.
  Future<Uint8List?> pickFile(List<String> mimeTypes) =>
      _call<Uint8List>('pickFile', <String, Object?>{'mimeTypes': mimeTypes});

  /// Text from a scanned QR code, or null. [prompt] shows under the camera.
  Future<String?> scanQr({String? prompt}) =>
      _call<String>('scanQr', <String, Object?>{'prompt': prompt});

  Future<bool> voiceAvailable() async =>
      await _call<bool>('voiceAvailable') ?? false;

  /// What the user said, through the phone's voice input, or null.
  Future<String?> voiceSearch({String? prompt}) =>
      _call<String>('voiceSearch', <String, Object?>{'prompt': prompt});

  /// supported, enabled, service (the password manager's name or null).
  Future<Map<Object?, Object?>> autofillStatus() async =>
      await _call<Map<Object?, Object?>>('autofillStatus') ??
      const <Object?, Object?>{};

  Future<void> openAutofillSettings() => _call<void>('openAutofillSettings');

  Future<bool> privateProfileSupported() async =>
      await _call<bool>('privateProfileSupported') ?? false;

  /// The site (registrable domain) of [host], as the blocker sees it.
  Future<String> siteOf(String host) async =>
      await _call<String>('siteOf', <String, Object?>{'host': host}) ?? host;

  /// Cookies, site storage and cache of normal tabs.
  Future<void> clearBrowsingData() => _call<void>('clearBrowsingData');

  /// Opens a link in another app. Returns a web address to load instead
  /// when no app can open it.
  Future<String?> openExternal(String url) =>
      _call<String>('openExternal', <String, Object?>{'url': url});

  Future<bool> isDefaultBrowser() async =>
      await _call<bool>('isDefaultBrowser') ?? false;

  Future<void> openDefaultBrowserSettings() =>
      _call<void>('openDefaultBrowserSettings');

  /// This phone's model ("Pixel 8"), the name other devices see.
  Future<String> deviceName() async =>
      await _call<String>('deviceName') ?? 'Android phone';

  // ---- B24: cookie auto-clear ----------------------------------------------

  /// Deletes cookies and site storage (local storage, IndexedDB, caches)
  /// of these hosts and their sites, in normal tabs. Private tabs have
  /// their own profile and are never touched.
  Future<void> clearSiteData(List<String> hosts) =>
      _call<void>('clearSiteData', <String, Object?>{'hosts': hosts});

  // ---- B30: the user's own block rules --------------------------------------

  /// Hosts the user blocks or never blocks, and a file of hosts from the
  /// extra filter lists (one per line), or null for none.
  Future<void> setUserRules({
    required List<String> blocked,
    required List<String> allowed,
    String? listsFile,
  }) => _call<void>('setUserRules', <String, Object?>{
    'blocked': blocked,
    'allowed': allowed,
    'listsFile': listsFile,
  });

  /// How many hosts the extra filter lists add (once loaded).
  Future<int> extraListSize() async => await _call<int>('extraListSize') ?? 0;

  // ---- B17: encrypted DNS ------------------------------------------------

  /// Android's Private DNS: active (bool), server (the provider's name when
  /// the user set one, else null).
  Future<Map<Object?, Object?>> privateDns() async =>
      await _call<Map<Object?, Object?>>('privateDns') ??
      const <Object?, Object?>{};

  /// Android's network settings, where Private DNS is.
  Future<void> openNetworkSettings() => _call<void>('openNetworkSettings');

  // ---- B29: private tab extras ---------------------------------------------

  /// [secure] blocks screenshots and screen recording; [hideRecents]
  /// blanks the app's preview in recent apps.
  Future<void> setWindowPrivacy({
    required bool secure,
    required bool hideRecents,
  }) => _call<void>('setWindowPrivacy', <String, Object?>{
    'secure': secure,
    'hideRecents': hideRecents,
  });

  // ---- B25: the other ZT apps ----------------------------------------------

  /// Which of [packages] are installed.
  Future<Set<String>> installedApps(List<String> packages) async =>
      (await _call<List<Object?>>('installedApps', <String, Object?>{
                'packages': packages,
              }) ??
              const <Object?>[])
          .whereType<String>()
          .toSet();

  /// Hands something to another app on the phone (nothing leaves it):
  /// [action] is 'send' (text), 'dial' (a number) or 'contact' (a new
  /// contact with this number). False when the app couldn't take it.
  Future<bool> sendToApp({
    required String package,
    required String action,
    String? text,
    String? subject,
    String? phone,
  }) async =>
      await _call<bool>('sendToApp', <String, Object?>{
        'package': package,
        'action': action,
        'text': text,
        'subject': subject,
        'phone': phone,
      }) ??
      false;

  /// The text selected on the page, or null.
  Future<String?> selection(String tabId) async {
    final String? raw = await _call<String>('selection', <String, Object?>{
      'tabId': tabId,
    });
    if (raw == null || raw == 'null') return null;
    try {
      final Object? v = jsonDecode(raw);
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    } on FormatException {
      return null;
    }
  }

  // ---- B16: translation -----------------------------------------------------

  /// The page's declared language (`lang`) and a sample of its text.
  Future<({String lang, String sample})?> pageLanguage(String tabId) async {
    final String? raw = await _call<String>('pageLanguage', <String, Object?>{
      'tabId': tabId,
    });
    if (raw == null) return null;
    try {
      final Object? v = jsonDecode(raw);
      if (v is! Map) return null;
      return (
        lang: v['lang'] as String? ?? '',
        sample: v['sample'] as String? ?? '',
      );
    } on FormatException {
      return null;
    }
  }

  /// Translates the page on the phone, with the models in [modelsDir].
  /// False when the page's JavaScript is off.
  Future<bool> translatePage(
    String tabId,
    String from,
    String to,
    String modelsDir,
  ) async =>
      await _call<bool>('translatePage', <String, Object?>{
        'tabId': tabId,
        'from': from,
        'to': to,
        'modelsDir': modelsDir,
      }) ??
      false;

  Future<void> showOriginal(String tabId) =>
      _call<void>('showOriginal', <String, Object?>{'tabId': tabId});

  /// The installed models changed.
  Future<void> translatorReset() => _call<void>('translatorReset');

  // ---- B27: read aloud -----------------------------------------------------

  /// Reads [parts] aloud with the phone's own text-to-speech, in
  /// [language] (a BCP-47 tag like "he" or "en-US"), from part [from].
  /// [title] shows in the notification.
  Future<bool> readAloudStart({
    required List<String> parts,
    required String title,
    String? language,
    double rate = 1.0,
    int from = 0,
    bool private = false,
  }) async =>
      await _call<bool>('readAloudStart', <String, Object?>{
        'parts': parts,
        'title': title,
        'private': private,
        'language': language,
        'rate': rate,
        'from': from,
      }) ??
      false;

  Future<void> readAloudPause() => _call<void>('readAloudPause');
  Future<void> readAloudResume() => _call<void>('readAloudResume');
  Future<void> readAloudStop() => _call<void>('readAloudStop');
  Future<void> readAloudSkip(int by) =>
      _call<void>('readAloudSkip', <String, Object?>{'by': by});
  Future<void> readAloudRate(double rate) =>
      _call<void>('readAloudRate', <String, Object?>{'rate': rate});

  // ---- B26: background play ----------------------------------------------

  /// Keep media playing in the background (with a notification), and the
  /// notification's texts in the app's language.
  Future<void> setMedia({
    required bool backgroundPlay,
    required Map<String, String> labels,
  }) => _call<void>('setMedia', <String, Object?>{
    'backgroundPlay': backgroundPlay,
    'labels': labels,
  });

  /// Picture-in-picture for the video playing full screen now, if any.
  Future<bool> pictureInPicture() async =>
      await _call<bool>('pictureInPicture') ?? false;

  // ---- B41: user scripts ---------------------------------------------------

  /// The scripts to run (see UserScripts.toEngine); tabs pick them up for
  /// their next page.
  Future<void> setUserScripts(List<Map<String, Object?>> scripts) =>
      _call<void>('setUserScripts', <String, Object?>{'scripts': scripts});

  /// Deletes what a removed script stored on this phone.
  Future<void> forgetUserScript(String id) =>
      _call<void>('forgetUserScript', <String, Object?>{'id': id});

  /// No scripts and nothing they stored (signed out).
  Future<void> clearUserScripts() => _call<void>('clearUserScripts');

  /// Commands the page's scripts added to the menu.
  Future<List<ScriptCommand>> scriptCommands(String tabId) async =>
      <ScriptCommand>[
        for (final Object? m
            in await _call<List<Object?>>('scriptCommands', <String, Object?>{
                  'tabId': tabId,
                }) ??
                const <Object?>[])
          if (m is Map<Object?, Object?>)
            ScriptCommand(
              script: m['script'] as String? ?? '',
              name: m['name'] as String? ?? '',
              scriptId: m['s'] as String? ?? '',
              id: m['i'] as int? ?? 0,
            ),
      ];

  Future<void> runScriptCommand(String tabId, ScriptCommand c) => _call<void>(
    'runScriptCommand',
    <String, Object?>{'tabId': tabId, 's': c.scriptId, 'i': c.id},
  );
}

/// A command a user script added to the menu (GM_registerMenuCommand).
class ScriptCommand {
  const ScriptCommand({
    required this.script,
    required this.name,
    required this.scriptId,
    required this.id,
  });

  final String script;
  final String name;
  final String scriptId;
  final int id;
}

/// Read aloud, as the engine reports it.
class ReadAloudState {
  const ReadAloudState({
    this.status = 'idle',
    this.part = 0,
    this.parts = 0,
    this.error,
  });

  /// idle, speaking, paused or done.
  final String status;
  final int part;
  final int parts;

  /// noVoice (no voice for the language), failed, or null.
  final String? error;

  bool get active => status == 'speaking' || status == 'paused';

  static ReadAloudState fromMap(Map<Object?, Object?> m) => ReadAloudState(
    status: m['status'] as String? ?? 'idle',
    part: m['part'] as int? ?? 0,
    parts: m['parts'] as int? ?? 0,
    error: m['error'] as String?,
  );
}

/// What came of opening or sharing a downloaded file.
enum DownloadResult {
  done,
  noApp,
  missing,
  failed;

  /// The engine's answer: "opened", "noApp", "missing" or "failed" (and
  /// true/false from older engines).
  static DownloadResult parse(Object? v) => switch (v) {
    'opened' || true => done,
    'noApp' => noApp,
    'missing' => missing,
    _ => failed,
  };
}

/// How handing a file straight to another app went (B40).
enum SendResult {
  sent,

  /// The app isn't on this phone.
  notInstalled,

  /// The app doesn't take this kind of file.
  unsupported,
  missing,
  failed;

  static SendResult parse(Object? v) => switch (v) {
    'opened' => sent,
    'notInstalled' => notInstalled,
    'unsupported' => unsupported,
    'missing' => missing,
    _ => failed,
  };
}

final browserEngineProvider = Provider<BrowserEngine>((ref) => BrowserEngine());

/// A download that finished, for a message on the browser screen.
class DownloadEvent {
  const DownloadEvent({
    required this.key,
    required this.name,
    required this.status,
    this.private = false,
    this.error,
    this.openWhenDone = false,
  });

  factory DownloadEvent.fromMap(Map<Object?, Object?> m) => DownloadEvent(
    key: m['key'] as String? ?? '',
    name: m['name'] as String? ?? '',
    status: m['status'] as String? ?? 'failed',
    private: m['private'] as bool? ?? false,
    error: m['error'] as String?,
    openWhenDone: m['openWhenDone'] as bool? ?? false,
  );

  final String key;
  final String name;

  /// done or failed.
  final String status;
  final bool private;

  /// Why it failed: network, http, space or gone.
  final String? error;
  final bool openWhenDone;

  bool get done => status == 'done';
}
