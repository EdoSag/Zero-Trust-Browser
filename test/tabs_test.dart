import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/cookie_auto_clear.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
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

  @override
  Future<void> visited(String? url) async {}

  @override
  Future<void> sweep(Iterable<String?> openUrls) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('zt_browser/engine');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    _Counted.seen.clear();
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
    });
    final BrowserTab now = c.read(tabsProvider).current!;
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
}
