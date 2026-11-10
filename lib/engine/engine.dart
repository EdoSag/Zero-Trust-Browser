import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Something a tab's page did: new state, a favicon, a link to open...
class TabEvent {
  const TabEvent(this.tabId, this.type, this.data);

  final String tabId;

  /// state, favicon, visited, openTab, contextMenu, external, download,
  /// httpsFailed, sslError, find, crashed.
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
  }) => _call<void>('setPrivacy', <String, Object?>{
    'blockTrackers': blockTrackers,
    'httpsOnly': httpsOnly,
    'allowedSites': allowedSites,
  });

  Future<int> blocklistSize() async => await _call<int>('blocklistSize') ?? 0;

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
