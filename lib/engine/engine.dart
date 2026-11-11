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
    }
    return null;
  }

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
  /// or 'qr'.
  Future<String?> consumeWidgetAction() => _call<String>('consumeWidgetAction');

  Future<void> createTab(
    String tabId, {
    required bool private,
    String? url,
    bool desktop = false,
  }) => _call<void>('createTab', <String, Object?>{
    'tabId': tabId,
    'private': private,
    'url': url,
    'desktop': desktop,
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
  }) => _call<void>('setPrivacy', <String, Object?>{
    'stripTracking': stripTracking,
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

  /// Page text size (percent) and darkening of pages in dark mode.
  Future<void> setDisplay({required int textZoom, required bool darkPages}) =>
      _call<void>('setDisplay', <String, Object?>{
        'textZoom': textZoom,
        'darkPages': darkPages,
      });

  /// The tab now on screen: the engine keeps it, and unloads old ones.
  Future<void> select(String tabId) =>
      _call<void>('select', <String, Object?>{'tabId': tabId});

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
  Future<bool> openDownload(String key) async =>
      await _call<bool>('openDownload', <String, Object?>{'key': key}) ?? false;
  Future<bool> shareDownload(String key) async =>
      await _call<bool>('shareDownload', <String, Object?>{'key': key}) ??
      false;
  Future<void> deleteDownload(String key) =>
      _call<void>('deleteDownload', <String, Object?>{'key': key});

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
  }) async =>
      await _call<bool>('readAloudStart', <String, Object?>{
        'parts': parts,
        'title': title,
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

final browserEngineProvider = Provider<BrowserEngine>((ref) => BrowserEngine());
