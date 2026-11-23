import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/apply_settings.dart';
import 'package:zerotrust_browser/browser/cookie_auto_clear.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// Collects what the tabs count for the privacy report.
class _Counted extends PrivacyReportRecorder {
  _Counted(super.ref);

  static final List<(String, int)> seen = <(String, int)>[];

  @override
  void add(String site, int count, {DateTime? now}) => seen.add((site, count));
}

/// Cookie auto-clear is off in these tests (it reads the account's
/// settings store, which isn't there).
class _NoAutoClear extends CookieAutoClear {
  _NoAutoClear(super.ref);

  static final List<String?> seen = <String?>[];

  @override
  Future<void> visited(String? url) async => seen.add(url);

  @override
  Future<void> sweep(Iterable<String?> openUrls) async {}
}

/// History isn't kept in these tests (it needs the account's vault).
class _NoHistory extends BrowserData {
  _NoHistory(super.ref);

  @override
  Future<void> recordVisit(String url, String? title) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('zt_browser/engine');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    _Counted.seen.clear();
    _NoAutoClear.seen.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
  });

  ProviderContainer container() {
    final ProviderContainer c = ProviderContainer(
      overrides: [
        browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
        privacyReportRecorderProvider.overrideWith(_Counted.new),
        cookieAutoClearProvider.overrideWith(_NoAutoClear.new),
        browserDataProvider.overrideWith(_NoHistory.new),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> nativeEvent(Map<String, Object?> data) async {
    final ByteData msg = const StandardMethodCodec().encodeMethodCall(
      MethodCall('tabEvent', data),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zt_browser/engine', msg, (_) {});
  }

  test('page activity from the engine reaches whoever listens', () async {
    final ProviderContainer c = container();
    final BrowserEngine engine = c.read(browserEngineProvider);
    int heard = 0;
    final StreamSubscription<void> sub = engine.pageActivity.listen(
      (_) => heard++,
    );
    addTearDown(sub.cancel);
    final ByteData msg = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('pageActivity'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('zt_browser/engine', msg, (_) {});
    await Future<void>.delayed(Duration.zero);
    expect(heard, 1);
  });

  test('opening a tab creates its WebView and shows it', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab t = await tabs.open(url: 'https://a.org');
    expect(c.read(tabsProvider).current?.id, t.id);
    expect(calls.first.method, 'createTab');
    expect(calls.first.arguments['url'], 'https://a.org');
    expect(calls.first.arguments['private'], false);
    // The engine learns which tab is on screen (to unload old ones).
    expect(calls[1].method, 'select');
    expect(calls[1].arguments['tabId'], t.id);
  });

  test('closing the current tab shows a neighbour of the same kind', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab a = await tabs.open(url: 'https://a.org');
    await tabs.open(private: true);
    final BrowserTab b = await tabs.open(url: 'https://b.org');
    await tabs.close(b.id);
    expect(c.read(tabsProvider).current?.id, a.id);
    expect(
      calls.map((MethodCall m) => m.method),
      containsAllInOrder(<String>['closeTab', 'select']),
    );
  });

  test('closeAll(private) leaves normal tabs', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    await tabs.open(url: 'https://a.org');
    await tabs.open(private: true);
    await tabs.open(private: true);
    await tabs.closeAll(private: true);
    expect(c.read(tabsProvider).private, isEmpty);
    expect(c.read(tabsProvider).normal, hasLength(1));
  });

  test('page state from the engine updates the tab', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab t = await tabs.open(url: 'https://a.org');
    await nativeEvent(<String, Object?>{
      'tabId': t.id,
      'type': 'state',
      'url': 'https://a.org/page',
      'title': 'A page',
      'progress': 100,
      'loading': false,
      'canGoBack': true,
      'canGoForward': false,
      'secure': true,
      'blocked': 7,
      'desktop': false,
      'codeField': true,
    });
    final BrowserTab now = c.read(tabsProvider).current!;
    expect(now.codeField, isTrue);
    expect(now.url, 'https://a.org/page');
    expect(now.title, 'A page');
    expect(now.blocked, 7);
    expect(now.secure, isTrue);
    expect(now.canGoBack, isTrue);
    expect(_Counted.seen, <(String, int)>[('a.org', 7)]);
  });

  test(
    'the privacy report counts what is new, without private sites',
    () async {
      final ProviderContainer c = container();
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(url: 'https://a.org');
      Future<void> blocked(String id, int n, [String? url]) =>
          nativeEvent(<String, Object?>{
            'tabId': id,
            'type': 'state',
            'blocked': n,
            'url': ?url,
          });
      await blocked(t.id, 3);
      await blocked(t.id, 3);
      await blocked(t.id, 5);
      // A new page starts counting from zero again.
      await blocked(t.id, 0, 'https://www.b.org/');
      await blocked(t.id, 2);
      final BrowserTab p = await tabs.open(
        url: 'https://secret.org',
        private: true,
      );
      await blocked(p.id, 4);
      expect(_Counted.seen, <(String, int)>[
        ('a.org', 3),
        ('a.org', 2),
        ('b.org', 2),
        ('', 4),
      ]);
    },
  );

  test('a page opened by its address is noted for cookie clearing', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab t = await tabs.open(url: 'https://a.org');
    final BrowserTab p = await tabs.open(url: 'https://b.org', private: true);
    for (final BrowserTab tab in <BrowserTab>[t, p]) {
      // The address is the one the tab was opened with: no change.
      await nativeEvent(<String, Object?>{
        'tabId': tab.id,
        'type': 'state',
        'url': tab.url,
        'loading': false,
      });
      await nativeEvent(<String, Object?>{
        'tabId': tab.id,
        'type': 'visited',
        'url': tab.url,
        'title': 'A',
      });
    }
    expect(_NoAutoClear.seen, <String?>['https://a.org']);
  });

  test('a pop-up opens as a new tab of the same kind', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab t = await tabs.open(private: true);
    await nativeEvent(<String, Object?>{
      'tabId': t.id,
      'type': 'openTab',
      'url': 'https://b.org',
      'private': true,
    });
    await Future<void>.delayed(Duration.zero);
    expect(c.read(tabsProvider).private, hasLength(2));
    expect(c.read(tabsProvider).current?.url, 'https://b.org');
  });

  test('a crashed tab comes back with a fresh WebView', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab t = await tabs.open(url: 'https://a.org');
    await nativeEvent(<String, Object?>{'tabId': t.id, 'type': 'crashed'});
    expect(c.read(tabsProvider).current?.crashed, isTrue);
    calls.clear();
    await tabs.revive(t.id);
    expect(c.read(tabsProvider).current?.crashed, isFalse);
    expect(calls.single.method, 'createTab');
    expect(calls.single.arguments['tabId'], t.id);
  });

  test('an unloaded tab reloads, with its history, when shown', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab a = await tabs.open(url: 'https://a.org');
    final BrowserTab b = await tabs.open(url: 'https://b.org');
    await nativeEvent(<String, Object?>{'tabId': a.id, 'type': 'unloaded'});
    expect(tabs.byId(a.id)!.unloaded, isTrue);
    calls.clear();
    tabs.select(a.id);
    await Future<void>.delayed(Duration.zero);
    expect(tabs.byId(a.id)!.unloaded, isFalse);
    expect(calls.first.method, 'createTab');
    expect(calls.first.arguments['tabId'], a.id);
    expect(calls[1].method, 'select');
    expect(c.read(tabsProvider).currentId, a.id);
    expect(tabs.byId(b.id)!.unloaded, isFalse);
  });

  test('tabs join, leave and list groups', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab a = await tabs.open(url: 'https://a.org');
    final BrowserTab b = await tabs.open(url: 'https://b.org', group: 'Trip');
    tabs.setGroup(a.id, ' Work ');
    expect(tabs.byId(a.id)!.group, 'Work');
    expect(c.read(tabsProvider).groups, <String>['Work', 'Trip']);
    tabs.setGroup(a.id, '');
    expect(tabs.byId(a.id)!.group, isNull);
    // Links opened from a grouped tab stay in its group.
    await nativeEvent(<String, Object?>{
      'tabId': b.id,
      'type': 'openTab',
      'url': 'https://c.org',
      'private': false,
    });
    await Future<void>.delayed(Duration.zero);
    expect(c.read(tabsProvider).current?.group, 'Trip');
  });

  test('private tabs never join a group', () async {
    final ProviderContainer c = container();
    final BrowserTab p = await c
        .read(tabsProvider.notifier)
        .open(private: true, group: 'Work');
    expect(p.group, isNull);
  });

  test('tabs unused for N days close, but never the one on screen', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab old = await tabs.open(url: 'https://old.org');
    final BrowserTab fresh = await tabs.open(url: 'https://new.org');
    final DateTime later = DateTime.now().add(const Duration(days: 8));
    tabs.select(old.id);
    tabs.select(fresh.id);
    // Both were used "now"; eight days later both count as unused, but
    // the one on screen stays.
    final int closed = await tabs.closeUnused(7, now: later);
    expect(closed, 1);
    expect(c.read(tabsProvider).tabs.single.id, fresh.id);
  });

  group('browser identity (B42)', () {
    const CustomIdentity mine = CustomIdentity(
      id: 'abc',
      name: 'Work laptop',
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0',
    );

    ProviderContainer withSettings(BrowserSettings s) {
      final ProviderContainer c = ProviderContainer(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
          privacyReportRecorderProvider.overrideWith(_Counted.new),
          cookieAutoClearProvider.overrideWith(_NoAutoClear.new),
          browserDataProvider.overrideWith(_NoHistory.new),
          browserSettingsProvider.overrideWithValue(s),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Map<Object?, Object?>? identityIn(MethodCall call) =>
        call.arguments['identity'] as Map<Object?, Object?>?;

    String? specId(MethodCall call) =>
        (identityIn(call)?['spec'] as Map<Object?, Object?>?)?['id'] as String?;

    test('a tab follows the settings until it is given its own', () async {
      final ProviderContainer c = withSettings(const BrowserSettings());
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(url: 'https://a.org');
      expect(t.identity, isNull);
      // Nothing about identity goes to the engine for an ordinary tab.
      expect(identityIn(calls.first), isNull);
      expect(
        calls.where((MethodCall m) => m.method == 'setTabIdentity'),
        isEmpty,
      );

      await tabs.setIdentity(t.id, 'firefox-windows');
      expect(c.read(tabsProvider).byId(t.id)!.identity, 'firefox-windows');
      expect(calls.last.method, 'setTabIdentity');
      expect(calls.last.arguments['tabId'], t.id);
      expect(specId(calls.last), 'firefox-windows');

      // The default, in this tab only: an identity with nothing in it.
      await tabs.setIdentity(t.id, 'default');
      expect(identityIn(calls.last), isEmpty);

      // Back to the settings.
      await tabs.setIdentity(t.id, null);
      expect(c.read(tabsProvider).byId(t.id)!.identity, isNull);
      expect(calls.last.method, 'setTabIdentity');
      expect(identityIn(calls.last), isNull);
    });

    test('a page opened from a tab keeps that tab\'s identity', () async {
      final ProviderContainer c = withSettings(const BrowserSettings());
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(url: 'https://a.org');
      await tabs.setIdentity(t.id, 'safari-iphone');
      calls.clear();
      await nativeEvent(<String, Object?>{
        'tabId': t.id,
        'type': 'openTab',
        'url': 'https://b.org',
      });
      await Future<void>.delayed(Duration.zero);
      final BrowserTab opened = c.read(tabsProvider).current!;
      expect(opened.id, isNot(t.id));
      expect(opened.identity, 'safari-iphone');
      final MethodCall create = calls.firstWhere(
        (MethodCall m) => m.method == 'createTab',
      );
      expect(specId(create), 'safari-iphone');
    });

    test('a tab that crashed keeps its identity when it comes back', () async {
      final ProviderContainer c = withSettings(const BrowserSettings());
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(
        url: 'https://a.org',
        identity: 'chrome-windows',
      );
      expect(specId(calls.first), 'chrome-windows');
      calls.clear();
      await tabs.revive(t.id);
      expect(calls.single.method, 'createTab');
      expect(specId(calls.single), 'chrome-windows');
    });

    test('the engine says which identity a tab really has', () async {
      final ProviderContainer c = withSettings(const BrowserSettings());
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(url: 'https://a.org');
      expect(t.shownIdentity, 'default');
      await nativeEvent(<String, Object?>{
        'tabId': t.id,
        'type': 'state',
        'url': 'https://a.org/',
        'identity': 'firefox-android',
      });
      // From a site rule or the settings: the tab has no choice of its own.
      expect(c.read(tabsProvider).byId(t.id)!.shownIdentity, 'firefox-android');
      expect(c.read(tabsProvider).byId(t.id)!.identity, isNull);
    });

    test(
      'an edited identity of the user\'s own reaches the tabs using it',
      () async {
        final ProviderContainer c = withSettings(
          const BrowserSettings().copyWith(
            customIdentities: <CustomIdentity>[mine],
          ),
        );
        final TabsController tabs = c.read(tabsProvider.notifier);
        final BrowserTab own = await tabs.open(
          url: 'https://a.org',
          identity: 'custom:abc',
        );
        await tabs.open(url: 'https://b.org');
        expect(specId(calls.first), 'custom:abc');
        calls.clear();
        await tabs.refreshIdentities();
        // Only the tab with an identity of its own is told again.
        expect(calls.single.method, 'setTabIdentity');
        expect(calls.single.arguments['tabId'], own.id);
        expect(
          (identityIn(calls.single)!['spec']! as Map<Object?, Object?>)['ua'],
          mine.userAgent,
        );
      },
    );

    test('a tab whose own identity was deleted gets the default', () async {
      final ProviderContainer c = withSettings(const BrowserSettings());
      final TabsController tabs = c.read(tabsProvider.notifier);
      final BrowserTab t = await tabs.open(
        url: 'https://a.org',
        identity: 'custom:gone',
      );
      expect(identityIn(calls.first), isEmpty);
      calls.clear();
      await tabs.refreshIdentities();
      expect(calls.single.arguments['tabId'], t.id);
      expect(identityIn(calls.single), isEmpty);
    });
  });

  group('settings to engine: browser identity (B42)', () {
    final DateTime now = DateTime.utc(2026, 11, 20);

    test(
      'the default with no site rules: nothing for the engine to do',
      () async {
        await applyIdentity(
          BrowserEngine(channel),
          const BrowserSettings(),
          now: now,
        );
        expect(calls.single.method, 'setIdentity');
        expect(calls.single.arguments['global'], isNull);
        expect(calls.single.arguments['rules'], isEmpty);
      },
    );

    test('an identity for all sites and one for a site', () async {
      await applyIdentity(
        BrowserEngine(channel),
        const BrowserSettings().copyWith(
          identity: 'random-computer',
          identityRules: <String, String>{
            'example.com': 'safari-iphone',
            'bank.example': 'default',
          },
        ),
        now: now,
      );
      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      final Map<Object?, Object?> global =
          args['global']! as Map<Object?, Object?>;
      expect(global['pool'], isA<List<Object?>>());
      final Map<Object?, Object?> rules =
          args['rules']! as Map<Object?, Object?>;
      expect(rules.keys, <String>['example.com', 'bank.example']);
      expect(
        ((rules['example.com']! as Map<Object?, Object?>)['spec']!
            as Map<Object?, Object?>)['id'],
        'safari-iphone',
      );
      // "The default on this site", whatever the other sites get.
      expect(rules['bank.example'], isEmpty);
    });
  });
}
