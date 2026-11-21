import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/cookie_auto_clear.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/browser/tabs.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/identity_page.dart';

/// The settings as these tests keep them: in memory, no account.
class _Settings extends Notifier<BrowserSettings> {
  static BrowserSettings initial = const BrowserSettings();

  @override
  BrowserSettings build() => initial;

  void set(BrowserSettings s) => state = s;
}

final _settingsProvider = NotifierProvider<_Settings, BrowserSettings>(
  _Settings.new,
);

/// Saving writes to the settings above instead of the account's vault.
class _Data extends BrowserData {
  _Data(super.ref);

  @override
  Future<void> saveSettings(BrowserSettings s) async =>
      ref.read(_settingsProvider.notifier).set(s);

  @override
  Future<void> saveDeviceTabs(List<SavedTab> tabs) async {}

  @override
  Future<void> recordVisit(String url, String? title) async {}
}

class _NoReport extends PrivacyReportRecorder {
  _NoReport(super.ref);

  @override
  void add(String site, int count, {DateTime? now}) {}
}

class _NoAutoClear extends CookieAutoClear {
  _NoAutoClear(super.ref);

  @override
  Future<void> visited(String? url) async {}

  @override
  Future<void> sweep(Iterable<String?> openUrls) async {}
}

/// The Browser identity screens (B42), drawn with the look the app really
/// uses, on a phone-sized screen, against a fake engine.
///
/// The shared look makes filled and outlined buttons as wide as they can
/// be, so the tests check where things land, not only that they exist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/identity_engine');
  late List<MethodCall> calls;
  late ProviderContainer container;

  /// A Pixel-sized screen, in logical pixels.
  const Size pixel = Size(412, 915);

  /// A small, old phone.
  const Size small = Size(320, 480);

  const String phoneUa =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/142.0.0.0 Mobile Safari/537.36';
  const String windowsChrome =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  setUp(() {
    calls = <MethodCall>[];
    _Settings.initial = const BrowserSettings();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'identityInfo') {
            return <String, Object?>{
              'chrome': '142',
              'chromeFull': '142.0.7444.171',
              'android': '16',
              'defaultUa': phoneUa,
              'desktopUa': 'Mozilla/5.0 (X11; Linux x86_64) Chrome/142.0.0.0',
              'clientHints': true,
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  BrowserSettings settings() => container.read(_settingsProvider);

  List<MethodCall> sent(String method) => <MethodCall>[
    for (final MethodCall c in calls)
      if (c.method == method) c,
  ];

  /// Shows [home] in the app, with the app's look.
  ///
  /// [gestureBar] and [keyboard] are in logical pixels, like [screen].
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size screen = pixel,
    String locale = 'en',
    double gestureBar = 24,
    double keyboard = 0,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    tester.view.padding = FakeViewPadding(top: 40, bottom: gestureBar);
    tester.view.viewPadding = FakeViewPadding(top: 40, bottom: gestureBar);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    container = ProviderContainer(
      overrides: [
        browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
        browserSettingsProvider.overrideWith(
          (ref) => ref.watch(_settingsProvider),
        ),
        browserDataProvider.overrideWith(_Data.new),
        privacyReportRecorderProvider.overrideWith(_NoReport.new),
        cookieAutoClearProvider.overrideWith(_NoAutoClear.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
          locale: Locale(locale),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The part of the screen a person can see and touch: under the status
  /// bar, above the keyboard or the gesture bar.
  Rect visibleArea(WidgetTester tester) {
    final Size s = tester.view.physicalSize;
    final double bottom = tester.view.viewInsets.bottom > 0
        ? tester.view.viewInsets.bottom
        : tester.view.padding.bottom;
    return Rect.fromLTRB(
      0,
      tester.view.padding.top,
      s.width,
      s.height - bottom,
    );
  }

  /// Checks that [target] is drawn whole inside the visible area, at a size
  /// a finger can hit.
  void expectReachable(WidgetTester tester, Finder target) {
    expect(target, findsOneWidget);
    final Rect r = tester.getRect(target);
    final Rect area = visibleArea(tester);
    expect(r.width.isFinite && r.height.isFinite, isTrue, reason: '$r');
    expect(r.width, greaterThanOrEqualTo(88), reason: 'too narrow: $r');
    expect(r.height, greaterThanOrEqualTo(48), reason: 'too short: $r');
    expect(r.left, greaterThanOrEqualTo(area.left), reason: '$r in $area');
    expect(r.right, lessThanOrEqualTo(area.right), reason: '$r in $area');
    expect(r.top, greaterThanOrEqualTo(area.top), reason: '$r in $area');
    expect(r.bottom, lessThanOrEqualTo(area.bottom), reason: '$r in $area');
  }

  Finder key(String k) => find.byKey(ValueKey<String>(k));
  Finder choice(String value) => key('identity-choice-$value');

  /// Scrolls the open list of identities to [value] and taps it.
  Future<void> pick(WidgetTester tester, String value) async {
    await tester.ensureVisible(choice(value));
    await tester.pumpAndSettle();
    expectReachable(tester, choice(value));
    await tester.tap(choice(value));
    await tester.pumpAndSettle();
  }

  /// Scrolls the page's own list until [target] is on screen.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('Settings > Browser identity', () {
    testWidgets('by default: the phone\'s own Chrome, and nothing to shuffle', (
      WidgetTester tester,
    ) async {
      await pump(tester, const IdentityPage());
      expect(tester.takeException(), isNull);
      expectReachable(tester, key('identity-global'));
      expect(
        find.descendant(
          of: key('identity-global'),
          matching: find.text('Default'),
        ),
        findsOneWidget,
      );
      // What sites are told: the string as it really goes out.
      expect(
        tester.widget<SelectableText>(key('identity-seen-ua')).data,
        phoneUa,
      );
      expect(find.textContaining('Google Chrome 142'), findsOneWidget);
      expect(find.text('New random identities now'), findsNothing);
      // The card sits under the choice and inside the screen.
      final Rect card = tester.getRect(find.byType(Card));
      expect(
        card.top,
        greaterThanOrEqualTo(tester.getRect(key('identity-global')).bottom),
      );
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(pixel.width));
      // Looking at the page changes nothing in the engine.
      expect(sent('setIdentity'), isEmpty);
    });

    testWidgets('picking Firefox on Windows for all sites', (
      WidgetTester tester,
    ) async {
      await pump(tester, const IdentityPage());
      await tester.tap(key('identity-global'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The list opens as a sheet under the status bar, with the default
      // marked and the groups in order.
      final Rect sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(40));
      expect(sheet.bottom, lessThanOrEqualTo(pixel.height));
      expectReachable(tester, choice('default'));
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'default',
      );
      expect(
        tester.getRect(find.text('Phones and tablets')).top,
        lessThan(tester.getRect(find.text('Computers')).top),
      );
      expect(
        tester.getRect(find.text('Computers')).top,
        lessThan(tester.getRect(find.text('Random')).top),
      );
      // No group for the user's own identities while there are none.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Your own identities'),
        ),
        findsNothing,
      );

      await pick(tester, 'firefox-windows');
      expect(find.byType(BottomSheet), findsNothing);
      expect(settings().identity, 'firefox-windows');
      expect(
        find.descendant(
          of: key('identity-global'),
          matching: find.text('Firefox on Windows'),
        ),
        findsOneWidget,
      );
      final String seen = tester
          .widget<SelectableText>(key('identity-seen-ua'))
          .data!;
      expect(seen, startsWith('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:'));
      expect(seen, contains('Firefox/'));
      expect(find.textContaining('no Client Hints'), findsOneWidget);
    });

    testWidgets('a random identity can be shuffled', (
      WidgetTester tester,
    ) async {
      _Settings.initial = const BrowserSettings().copyWith(
        identity: 'random-phone',
      );
      await pump(tester, const IdentityPage());
      expect(
        find.descendant(
          of: key('identity-global'),
          matching: find.text('Random phone browser'),
        ),
        findsOneWidget,
      );
      // No single string to show.
      expect(key('identity-seen-ua'), findsNothing);
      expect(find.text('A different browser for each site.'), findsOneWidget);

      final Finder shuffle = find.widgetWithText(
        ListTile,
        'New random identities now',
      );
      expectReachable(tester, shuffle);
      await tester.tap(shuffle);
      await tester.pump();
      expect(sent('shuffleIdentity'), hasLength(1));
      expect(
        find.text('Sites get new random identities from now on'),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('a site gets its own identity, and loses it again', (
      WidgetTester tester,
    ) async {
      await pump(tester, const IdentityPage());
      await reveal(tester, key('identity-add-site'));
      await tester.tap(key('identity-add-site'));
      await tester.pumpAndSettle();

      // Not a site: the dialog says so and stays.
      await tester.enterText(find.byType(TextField), 'not a site');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(settings().identityRules, isEmpty);

      await tester.enterText(
        find.byType(TextField),
        'https://www.Example.com/a',
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      // The list of identities, named after the site.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('example.com'),
        ),
        findsOneWidget,
      );
      await pick(tester, 'chrome-windows');
      expect(settings().identityRules, <String, String>{
        'example.com': 'chrome-windows',
      });
      expect(settings().identity, 'default');

      final Finder row = find.widgetWithText(ListTile, 'example.com');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expectReachable(tester, row);
      expect(
        find.descendant(of: row, matching: find.text('Chrome on Windows')),
        findsOneWidget,
      );
      // The remove button is at the end of the row, inside it.
      final Finder remove = find.descendant(
        of: row,
        matching: find.byTooltip('Remove'),
      );
      final Rect r = tester.getRect(remove);
      expect(r.center.dx, greaterThan(pixel.width / 2));
      expect(r.right, lessThanOrEqualTo(pixel.width));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(settings().identityRules, isEmpty);
      expect(find.text('example.com'), findsNothing);
    });

    testWidgets('making an identity of your own, using it and deleting it', (
      WidgetTester tester,
    ) async {
      await pump(tester, const IdentityPage());
      await reveal(tester, key('identity-make-own'));
      await tester.tap(key('identity-make-own'));
      await tester.pumpAndSettle();
      await tester.enterText(key('identity-name'), 'Work laptop');
      await tester.enterText(key('identity-ua'), windowsChrome);
      await tester.pump();
      await tester.tap(key('identity-save'));
      await tester.pumpAndSettle();

      final CustomIdentity mine = settings().customIdentities.single;
      expect(mine.name, 'Work laptop');
      expect(mine.userAgent, windowsChrome);
      await tester.ensureVisible(find.text('Work laptop'));
      await tester.pumpAndSettle();
      expectReachable(tester, find.widgetWithText(ListTile, 'Work laptop'));

      // It is offered for all sites, in a group of its own.
      await tester.ensureVisible(key('identity-global'));
      await tester.pumpAndSettle();
      await tester.tap(key('identity-global'));
      await tester.pumpAndSettle();
      await pick(tester, 'custom:${mine.id}');
      expect(settings().identity, 'custom:${mine.id}');
      expect(
        tester.widget<SelectableText>(key('identity-seen-ua')).data,
        windowsChrome,
      );
      expect(find.textContaining('Google Chrome 131'), findsOneWidget);

      // Deleting it asks first, then all sites go back to the default.
      await tester.ensureVisible(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Work laptop?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(settings().customIdentities, isEmpty);
      expect(settings().identity, 'default');
    });

    testWidgets('in Hebrew the page mirrors and site names stay readable', (
      WidgetTester tester,
    ) async {
      _Settings.initial = const BrowserSettings().copyWith(
        identityRules: <String, String>{'example.com': 'safari-iphone'},
      );
      await pump(tester, const IdentityPage(), locale: 'he');
      expect(tester.takeException(), isNull);
      expect(find.text('זהות הדפדפן'), findsOneWidget);
      final Finder row = find.widgetWithText(ListTile, 'example.com');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.text('Safari ב-iPhone')),
        findsOneWidget,
      );
      // Mirrored: the remove button is at the left end of the row.
      final Rect remove = tester.getRect(
        find.descendant(of: row, matching: find.byType(IconButton)),
      );
      expect(remove.center.dx, lessThan(pixel.width / 2));
      expect(remove.left, greaterThanOrEqualTo(0));
    });
  });

  group('the editor for your own identity', () {
    CustomIdentity? result;
    bool closed = false;

    Widget opener({CustomIdentity? existing}) => Builder(
      builder: (BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CustomIdentity>(
                MaterialPageRoute<CustomIdentity>(
                  builder: (_) => IdentityEditorPage(existing: existing),
                ),
              );
              closed = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    );

    Future<void> open(
      WidgetTester tester, {
      CustomIdentity? existing,
      Size screen = pixel,
      String locale = 'en',
      double keyboard = 0,
      double textScale = 1,
    }) async {
      result = null;
      closed = false;
      await pump(
        tester,
        opener(existing: existing),
        screen: screen,
        locale: locale,
        keyboard: keyboard,
        textScale: textScale,
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    final Finder save = key('identity-save');
    final Finder cancel = key('identity-cancel');

    testWidgets('Save and Cancel are on screen, side by side', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('New identity'), findsOneWidget);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      final Rect s = tester.getRect(save);
      final Rect c = tester.getRect(cancel);
      expect(s.top, c.top);
      expect(s.left, greaterThan(c.right));
      // Under the fields.
      expect(s.top, greaterThan(tester.getRect(key('identity-ua')).bottom));
      expect(
        s.top,
        greaterThan(tester.getRect(key('identity-start-from')).bottom),
      );
      expectReachable(tester, key('identity-name'));
      expectReachable(tester, key('identity-ua'));
    });

    testWidgets('in Hebrew the buttons mirror: Cancel right, Save left', (
      WidgetTester tester,
    ) async {
      await open(tester, locale: 'he');
      expect(tester.takeException(), isNull);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      expect(tester.getRect(save).right, lessThan(tester.getRect(cancel).left));
    });

    testWidgets('a small phone, large text and the keyboard: the buttons '
        'stay above the keyboard and the rest scrolls', (
      WidgetTester tester,
    ) async {
      await open(tester, screen: small, keyboard: 200, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      final Rect before = tester.getRect(save);

      // Little room is left for the fields, so they scroll: first to the
      // user agent, then to what was worked out from it. The buttons do
      // not move.
      expect(tester.getRect(find.byType(ListView)).height, greaterThan(48));
      final Finder list = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(key('identity-ua'), 40, scrollable: list);
      await tester.enterText(key('identity-ua'), windowsChrome);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(save), before);
      // The end of the list (jumped to: a finger on the user agent field
      // moves the text inside that field).
      final ScrollPosition position = tester
          .state<ScrollableState>(list)
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      final Finder last = find.text('navigator.platform');
      await tester.pumpAndSettle();
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(before.top));
      expect(tester.getRect(save), before);
    });

    testWidgets('nothing typed: Save says what is missing and stays', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(find.text('Type a user agent'), findsNothing);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(closed, isFalse);
      expect(find.text('Type a user agent'), findsOneWidget);
      expectReachable(tester, save);

      await tester.enterText(key('identity-ua'), 'דפדפן/1.0');
      await tester.pumpAndSettle();
      expect(
        find.text('Only English letters, digits and punctuation'),
        findsOneWidget,
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(closed, isFalse);
    });

    testWidgets('typing a user agent shows what is worked out from it, '
        'and saves under a name made from it', (WidgetTester tester) async {
      await open(tester);
      expect(find.text('Worked out from it'), findsNothing);
      await tester.enterText(key('identity-ua'), '  $windowsChrome\n');
      await tester.pumpAndSettle();
      expect(find.text('Worked out from it'), findsOneWidget);
      expect(find.text('Chrome 131'), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget);
      expect(find.text('Google Chrome 131, Windows'), findsOneWidget);
      expect(find.text('Win32'), findsOneWidget);
      // Label and value share a line, the value after the label.
      final Rect label = tester.getRect(find.text('Browser'));
      final Rect value = tester.getRect(find.text('Chrome 131'));
      expect(value.left, greaterThanOrEqualTo(label.right));
      expect((value.top - label.top).abs(), lessThan(8));

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result!.userAgent, windowsChrome);
      expect(result!.name, 'Chrome on Windows');
      expect(result!.id, isNotEmpty);
    });

    testWidgets('{chrome} is filled with the phone\'s version in the preview', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.enterText(
        key('identity-ua'),
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/{chrome}.0.0.0 Safari/537.36',
      );
      await tester.pumpAndSettle();
      expect(find.text('Chrome 142'), findsOneWidget);
      expect(find.text('Google Chrome 142, Linux'), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      // Saved as typed, so it keeps up with the engine.
      expect(result!.userAgent, contains('Chrome/{chrome}.0.0.0'));
    });

    testWidgets('starting from a browser in the list fills both fields', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.tap(key('identity-start-from'));
      await tester.pumpAndSettle();
      final Rect sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(40));
      final Finder firefox = find.widgetWithText(
        ListTile,
        'Firefox on Windows',
      );
      await tester.scrollUntilVisible(
        firefox,
        80,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expectReachable(tester, firefox);
      await tester.tap(firefox);
      await tester.pumpAndSettle();
      final String ua = tester
          .widget<TextField>(key('identity-ua'))
          .controller!
          .text;
      expect(ua, startsWith('Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:'));
      expect(
        tester.widget<TextField>(key('identity-name')).controller!.text,
        'Firefox on Windows',
      );
      expect(find.text('None, like the real one'), findsOneWidget);
      expectReachable(tester, save);
    });

    testWidgets('editing keeps the id; Cancel changes nothing', (
      WidgetTester tester,
    ) async {
      const CustomIdentity mine = CustomIdentity(
        id: 'abc',
        name: 'Work laptop',
        userAgent: windowsChrome,
      );
      await open(tester, existing: mine);
      expect(find.text('Edit identity'), findsOneWidget);
      await tester.enterText(key('identity-name'), 'Office');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result!.id, 'abc');
      expect(result!.name, 'Office');
      expect(result!.userAgent, windowsChrome);

      await open(tester, existing: mine);
      await tester.enterText(key('identity-name'), 'Changed');
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('Browser identity from the page menu', () {
    late BrowserTab tab;

    Future<void> open(
      WidgetTester tester, {
      Size screen = pixel,
      String locale = 'en',
      String? url = 'https://news.example.com/today',
    }) async {
      await pump(
        tester,
        Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TextButton(
                onPressed: () => showTabIdentitySheet(
                  context,
                  ref,
                  ref.read(tabsProvider).current!,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
        screen: screen,
        locale: locale,
      );
      tab = (await tester.runAsync(
        () => container.read(tabsProvider.notifier).open(url: url),
      ))!;
      calls.clear();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    BrowserTab now() => container.read(tabsProvider).byId(tab.id)!;

    String? selected(WidgetTester tester) => tester
        .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
        .groupValue;

    testWidgets('this tab only: the engine is told, the settings are not', (
      WidgetTester tester,
    ) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      final Rect sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(40));
      expectReachable(tester, key('identity-scope'));
      expect(find.text('Until the tab is closed'), findsOneWidget);
      // It follows the settings until told otherwise, and says what
      // that is.
      expect(selected(tester), '+settings');
      expectReachable(tester, choice('+settings'));
      expect(
        find.descendant(
          of: choice('+settings'),
          matching: find.text('Default'),
        ),
        findsOneWidget,
      );
      // The choices sit under the switch between tab and site.
      expect(
        tester.getRect(choice('+settings')).top,
        greaterThanOrEqualTo(tester.getRect(key('identity-scope')).bottom),
      );

      await pick(tester, 'safari-iphone');
      expect(find.byType(BottomSheet), findsNothing);
      expect(now().identity, 'safari-iphone');
      expect(settings().identityRules, isEmpty);
      expect(settings().identity, 'default');
      final MethodCall call = sent('setTabIdentity').single;
      expect(call.arguments['tabId'], tab.id);
      final Map<Object?, Object?> identity =
          call.arguments['identity'] as Map<Object?, Object?>;
      expect(
        (identity['spec']! as Map<Object?, Object?>)['id'],
        'safari-iphone',
      );
      // "Desktop site" in that tab is Safari on a Mac.
      expect(
        (identity['desktop']! as Map<Object?, Object?>)['id'],
        'safari-mac',
      );

      // Opened again, it shows the tab's choice; "Same as Settings"
      // hands the tab back.
      calls.clear();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(selected(tester), 'safari-iphone');
      await pick(tester, '+settings');
      expect(now().identity, isNull);
      expect(sent('setTabIdentity').single.arguments['identity'], isNull);
    });

    testWidgets('the default in one tab, while the settings say otherwise', (
      WidgetTester tester,
    ) async {
      _Settings.initial = const BrowserSettings().copyWith(
        identity: 'firefox-android',
      );
      await open(tester);
      expect(
        find.descendant(
          of: choice('+settings'),
          matching: find.text('Firefox on Android'),
        ),
        findsOneWidget,
      );
      await pick(tester, 'default');
      expect(now().identity, 'default');
      // An identity with nothing in it: the default, not "as Settings".
      expect(sent('setTabIdentity').single.arguments['identity'], isEmpty);
    });

    testWidgets('this site, every time: a rule in the settings', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('This site'));
      await tester.pumpAndSettle();
      expect(
        find.text('Every time on news.example.com, in every tab'),
        findsOneWidget,
      );
      expect(selected(tester), '+settings');
      await pick(tester, 'chrome-windows');
      expect(settings().identityRules, <String, String>{
        'news.example.com': 'chrome-windows',
      });
      expect(now().identity, isNull);
      expect(sent('setTabIdentity'), isEmpty);

      // Opened again on "This site", the rule is marked; "Same as
      // Settings" removes it.
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This site'));
      await tester.pumpAndSettle();
      expect(selected(tester), 'chrome-windows');
      await pick(tester, '+settings');
      expect(settings().identityRules, isEmpty);
    });

    testWidgets('on the start page there is no site to choose for', (
      WidgetTester tester,
    ) async {
      await open(tester, url: null);
      expect(tester.takeException(), isNull);
      expect(key('identity-scope'), findsNothing);
      expectReachable(tester, choice('+settings'));
    });

    testWidgets('a small phone in Hebrew: the sheet fits and scrolls', (
      WidgetTester tester,
    ) async {
      await open(tester, screen: small, locale: 'he');
      expect(tester.takeException(), isNull);
      final Rect sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.top, greaterThanOrEqualTo(40));
      expect(sheet.bottom, lessThanOrEqualTo(small.height));
      expectReachable(tester, key('identity-scope'));
      expect(find.text('הכרטיסייה הזו'), findsOneWidget);
      // Mirrored: the radio mark is on the right of its name.
      final Rect row = tester.getRect(choice('+settings'));
      final Rect name = tester.getRect(
        find.descendant(
          of: choice('+settings'),
          matching: find.text('כמו בהגדרות'),
        ),
      );
      final Rect mark = tester.getRect(
        find.descendant(
          of: choice('+settings'),
          matching: find.byType(Radio<String>),
        ),
      );
      expect(mark.left, greaterThan(name.right));
      expect(mark.right, lessThanOrEqualTo(row.right));
      await pick(tester, 'random');
      expect(now().identity, 'random');
      final Map<Object?, Object?> identity =
          sent('setTabIdentity').single.arguments['identity']
              as Map<Object?, Object?>;
      expect(identity['pool'], isA<List<Object?>>());
    });
  });
}
