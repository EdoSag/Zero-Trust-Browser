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
}

final browserEngineProvider = Provider<BrowserEngine>((ref) => BrowserEngine());
