import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/engine/engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('zt_browser/engine');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
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
    expect(calls.single.method, 'createTab');
    expect(calls.single.arguments['url'], 'https://a.org');
    expect(calls.single.arguments['private'], false);
  });

  test('closing the current tab shows a neighbour of the same kind', () async {
    final ProviderContainer c = container();
    final TabsController tabs = c.read(tabsProvider.notifier);
    final BrowserTab a = await tabs.open(url: 'https://a.org');
    await tabs.open(private: true);
    final BrowserTab b = await tabs.open(url: 'https://b.org');
    await tabs.close(b.id);
    expect(c.read(tabsProvider).current?.id, a.id);
    expect(calls.last.method, 'closeTab');
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
}
