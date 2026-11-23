import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/fill_code_bar.dart';

/// "Fill code": the page asks for a one-time code, ZT Authenticator hands
/// it over, and the browser types it into the page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/fill_code_engine');
  late List<MethodCall> calls;
  late Object? answer;

  setUp(() {
    calls = <MethodCall>[];
    answer = 'filled';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return switch (call.method) {
            'fillCode' => answer,
            'authenticatorInstalled' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('every engine answer has a result; unknown ones are unavailable', () {
    expect(FillCodeResult.parse('filled'), FillCodeResult.filled);
    expect(FillCodeResult.parse('missing'), FillCodeResult.missing);
    expect(FillCodeResult.parse('canceled'), FillCodeResult.canceled);
    expect(FillCodeResult.parse('expired'), FillCodeResult.expired);
    expect(FillCodeResult.parse('invalid'), FillCodeResult.invalid);
    expect(FillCodeResult.parse('moved'), FillCodeResult.moved);
    expect(FillCodeResult.parse('noField'), FillCodeResult.noField);
    // An engine without Fill code (or off Android) answers nothing.
    expect(FillCodeResult.parse(null), FillCodeResult.unavailable);
  });

  test(
    'without the engine method, ZT Authenticator counts as missing',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      final BrowserEngine engine = BrowserEngine(channel);
      expect(await engine.authenticatorInstalled(), isFalse);
      expect(await engine.fillCode('t1'), FillCodeResult.unavailable);
    },
  );

  test('the page state says when a code field is showing', () {
    const BrowserTab tab = BrowserTab(id: 't1', private: false);
    expect(tab.codeField, isFalse);
    expect(tab.copyWith(codeField: true).codeField, isTrue);
    expect(tab.copyWith(codeField: true).copyWith().codeField, isTrue);
  });

  Future<List<String>> pump(
    WidgetTester tester, {
    String locale = 'en',
    double width = 412,
  }) async {
    final List<String> closed = <String>[];
    tester.view.physicalSize = Size(width, 915);
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
            body: Column(
              children: <Widget>[
                const Expanded(child: SizedBox()),
                FillCodeBar(
                  tab: const BrowserTab(
                    id: 't1',
                    private: false,
                    url: 'https://login.example.com/2fa',
                    codeField: true,
                  ),
                  onClose: () => closed.add('t1'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return closed;
  }

  testWidgets('the bar sits at the bottom with its button on screen', (
    tester,
  ) async {
    await pump(tester);
    final Rect bar = tester.getRect(find.byType(FillCodeBar));
    expect(bar.bottom, 915);
    expect(bar.height, 48);
    final Rect text = tester.getRect(
      find.text('This page asks for a sign-in code'),
    );
    final Rect button = tester.getRect(
      find.widgetWithText(TextButton, 'Fill code'),
    );
    final Rect close = tester.getRect(find.byTooltip('Close'));
    expect(button.width, greaterThan(40));
    // Text, then the button, then close, all in the bar's row.
    expect(text.right, lessThanOrEqualTo(button.left));
    expect(button.right, lessThanOrEqualTo(close.left));
    expect(close.right, lessThanOrEqualTo(412));
    for (final Rect r in <Rect>[text, button, close]) {
      expect(r.top, greaterThanOrEqualTo(bar.top));
      expect(r.bottom, lessThanOrEqualTo(bar.bottom));
    }
  });

  testWidgets('Fill code asks the engine for this tab and says it worked', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Fill code'));
    await tester.pumpAndSettle();
    final MethodCall call = calls.singleWhere(
      (MethodCall c) => c.method == 'fillCode',
    );
    expect(call.arguments, <String, Object?>{'tabId': 't1'});
    expect(find.text('Code filled in'), findsOneWidget);
  });

  testWidgets('closing ZT Authenticator without a code says nothing', (
    tester,
  ) async {
    answer = 'canceled';
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Fill code'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('no field found: the message says what to do', (tester) async {
    answer = 'noField';
    await pump(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Fill code'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Couldn't find where the code goes. Tap the code field and try again.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('close hides the bar for the page', (tester) async {
    final List<String> closed = await pump(tester);
    await tester.tap(find.byTooltip('Close'));
    expect(closed, <String>['t1']);
  });

  testWidgets('in Hebrew on a narrow phone the bar still fits', (tester) async {
    await pump(tester, locale: 'he', width: 320);
    final Rect button = tester.getRect(
      find.widgetWithText(TextButton, 'מילוי קוד'),
    );
    final Rect text = tester.getRect(find.text('הדף מבקש קוד כניסה'));
    expect(button.left, greaterThanOrEqualTo(0));
    expect(button.width, greaterThan(40));
    // Right to left: the text is right of the button.
    expect(text.left, greaterThanOrEqualTo(button.right));
    expect(tester.takeException(), isNull);
  });

  test('every result but canceled has a message in both languages', () async {
    for (final String code in <String>['en', 'he']) {
      final AppL10n l = await AppL10n.delegate.load(Locale(code));
      for (final FillCodeResult r in FillCodeResult.values) {
        final String? text = fillCodeMessage(l, r);
        if (r == FillCodeResult.canceled) {
          expect(text, isNull);
        } else {
          expect(text, isNotEmpty, reason: '$code $r');
        }
      }
    }
  });
}
