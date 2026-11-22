import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/site_sheet.dart';

/// B-7: the per-site shield panel lists what was blocked on the page, and
/// a blocked address can be allowed from there.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/shield_engine');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'blockedHosts') {
            return <String, int>{
              'ads.example.net': 2,
              'www.google-analytics.com': 7,
              'cdn.tracker.io': 2,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('most blocked first, ties by name', () {
    expect(
      sortBlocked(<String, int>{
        'b.com': 2,
        'a.com': 2,
        'c.com': 9,
      }).map((MapEntry<String, int> e) => e.key),
      <String>['c.com', 'a.com', 'b.com'],
    );
  });

  Future<List<String>> pump(
    WidgetTester tester, {
    String locale = 'en',
    int count = 11,
  }) async {
    final List<String> allowed = <String>[];
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlockedOnPage(
                tabId: 't1',
                count: count,
                onAllow: (String h) async => allowed.add(h),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return allowed;
  }

  testWidgets('opens to the blocked addresses, most first', (tester) async {
    await pump(tester);
    expect(find.text('11 trackers and ads blocked'), findsOneWidget);
    await tester.tap(find.text('11 trackers and ads blocked'));
    await tester.pumpAndSettle();
    expect(
      calls
          .where((MethodCall c) => c.method == 'blockedHosts')
          .single
          .arguments,
      <String, Object?>{'tabId': 't1'},
    );
    final double ga = tester
        .getTopLeft(find.text('www.google-analytics.com'))
        .dy;
    final double ads = tester.getTopLeft(find.text('ads.example.net')).dy;
    final double cdn = tester.getTopLeft(find.text('cdn.tracker.io')).dy;
    expect(ga, lessThan(ads));
    expect(ads, lessThan(cdn));
    expect(find.text('7 requests'), findsOneWidget);
  });

  testWidgets('Allow is on screen beside its address and allows it', (
    tester,
  ) async {
    final List<String> allowed = await pump(tester);
    await tester.tap(find.text('11 trackers and ads blocked'));
    await tester.pumpAndSettle();
    final Finder allow = find.widgetWithText(TextButton, 'Allow').first;
    final Rect box = tester.getRect(allow);
    expect(box.width, greaterThan(40));
    expect(box.right, lessThanOrEqualTo(412));
    // Same row as the first (most blocked) address.
    final Rect host = tester.getRect(find.text('www.google-analytics.com'));
    expect(box.top, lessThan(host.bottom));
    expect(box.bottom, greaterThan(host.top));
    await tester.tap(allow);
    expect(allowed, <String>['www.google-analytics.com']);
  });

  testWidgets('in Hebrew the list fits too', (tester) async {
    await pump(tester, locale: 'he');
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    final Rect allow = tester.getRect(
      find.widgetWithText(TextButton, 'אפשר').first,
    );
    expect(allow.left, greaterThanOrEqualTo(0));
    expect(allow.width, greaterThan(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing blocked: no list to open', (tester) async {
    await pump(tester, count: 0);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(calls, isEmpty);
  });
}
