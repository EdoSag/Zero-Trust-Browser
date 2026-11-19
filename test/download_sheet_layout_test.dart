import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/download_sheet.dart';

/// Where the buttons of the "Save this file?" sheet (B35) land on a phone,
/// drawn with the look the app really uses.
///
/// The shared Zero-Trust look makes filled buttons as wide as they can be.
/// In a plain row that is "endlessly wide", so the Save button was never
/// drawn and nothing could be downloaded. These tests use that look and
/// check positions, not only that the button exists.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A Pixel-sized screen, in logical pixels.
  const Size pixel = Size(412, 915);

  /// A small, old phone.
  const Size small = Size(320, 480);

  const DownloadRequest apk = DownloadRequest(
    requestId: 1,
    name: 'zero-trust-camera-0.8.1-build1028.apk',
    mime: 'application/vnd.android.package-archive',
    size: 99700000,
    url: 'https://release-assets.githubusercontent.com/zero-trust-camera.apk',
  );

  /// The worst case: every warning at once, from a private tab.
  const DownloadRequest worst = DownloadRequest(
    requestId: 2,
    name: 'holiday-photo.jpg.apk',
    mime: 'application/vnd.android.package-archive',
    size: -1,
    url: 'http://files.example.com/holiday-photo.jpg.apk',
    private: true,
  );

  late DownloadChoice? result;
  late bool closed;

  /// Opens the sheet over a page with the app's look.
  ///
  /// [gestureBar] and [keyboard] are in logical pixels, like [screen].
  Future<void> open(
    WidgetTester tester,
    DownloadRequest r, {
    Size screen = pixel,
    String locale = 'en',
    double gestureBar = 24,
    double keyboard = 0,
    double textScale = 1,
  }) async {
    result = null;
    closed = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = screen;
    tester.view.padding = FakeViewPadding(top: 40, bottom: gestureBar);
    tester.view.viewPadding = FakeViewPadding(top: 40, bottom: gestureBar);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      MaterialApp(
        theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
        locale: Locale(locale),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TextButton(
                onPressed: () async {
                  result = await showDownloadSheet(context, r);
                  closed = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
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

  /// Checks that [button] is drawn whole inside the visible area, at a size
  /// a finger can hit.
  void expectReachable(WidgetTester tester, Finder button) {
    expect(button, findsOneWidget);
    final Rect r = tester.getRect(button);
    final Rect area = visibleArea(tester);
    expect(r.width.isFinite && r.height.isFinite, isTrue, reason: '$r');
    expect(r.width, greaterThanOrEqualTo(88), reason: 'too narrow: $r');
    expect(r.height, greaterThanOrEqualTo(48), reason: 'too short: $r');
    expect(r.left, greaterThanOrEqualTo(area.left), reason: '$r in $area');
    expect(r.right, lessThanOrEqualTo(area.right), reason: '$r in $area');
    expect(r.top, greaterThanOrEqualTo(area.top), reason: '$r in $area');
    expect(r.bottom, lessThanOrEqualTo(area.bottom), reason: '$r in $area');
  }

  final Finder save = find.byKey(const ValueKey<String>('download-save'));
  final Finder cancel = find.byKey(const ValueKey<String>('download-cancel'));

  group('Save this file? sheet on a phone, with the app look', () {
    testWidgets('an app file: "Save anyway" is on screen, beside Cancel, '
        'and saves', (WidgetTester tester) async {
      await open(tester, apk);
      expect(tester.takeException(), isNull);
      expect(find.text('Save anyway'), findsOneWidget);
      expectReachable(tester, save);
      expectReachable(tester, cancel);

      final Rect s = tester.getRect(save);
      final Rect c = tester.getRect(cancel);
      // Side by side on one line, Save after Cancel, not on top of it.
      expect(s.top, c.top);
      expect(s.left, greaterThan(c.right));
      // Under everything else in the sheet.
      expect(
        s.top,
        greaterThan(tester.getRect(find.text('Open when done')).bottom),
      );
      expect(
        s.top,
        greaterThan(
          tester.getRect(find.byIcon(Icons.warning_amber_rounded)).bottom,
        ),
      );

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result?.name, 'zero-trust-camera-0.8.1-build1028.apk');
    });

    testWidgets('an ordinary file: Save is on screen and saves', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        const DownloadRequest(
          requestId: 3,
          name: 'report.pdf',
          mime: 'application/pdf',
          size: 2500000,
          url: 'https://files.example.com/report.pdf',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Save'), findsOneWidget);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.name, 'report.pdf');
    });

    testWidgets('in Hebrew the buttons mirror: Cancel right, Save left', (
      WidgetTester tester,
    ) async {
      await open(tester, apk, locale: 'he');
      expect(tester.takeException(), isNull);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      expect(tester.getRect(save).right, lessThan(tester.getRect(cancel).left));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
    });

    testWidgets('with the keyboard open, the buttons stay above it', (
      WidgetTester tester,
    ) async {
      await open(tester, apk, keyboard: 320);
      expect(tester.takeException(), isNull);
      expectReachable(tester, save);
      expectReachable(tester, cancel);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
    });

    testWidgets('every warning, a private tab, a small phone, large text '
        'and the keyboard: the buttons stay put and the rest scrolls', (
      WidgetTester tester,
    ) async {
      await open(tester, worst, screen: small, keyboard: 200, textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(worst.warnings.length, greaterThanOrEqualTo(3));
      expectReachable(tester, save);
      expectReachable(tester, cancel);

      // The sheet stays under the status bar.
      final Rect sheet = tester.getRect(find.byType(DownloadSheet));
      expect(sheet.top, greaterThanOrEqualTo(40));

      // The last choice is out of view at first; scrolling brings it in,
      // and the buttons do not move.
      final Rect before = tester.getRect(save);
      final Finder openWhenDone = find.text('Open when done');
      await tester.scrollUntilVisible(
        openWhenDone,
        60,
        // The sheet's own scroller (the name field has one inside it too).
        scrollable: find
            .descendant(
              of: find.byType(DownloadSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(openWhenDone).bottom,
        lessThanOrEqualTo(before.top),
      );
      expect(tester.getRect(save), before);

      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.keepPrivate, isTrue);
    });

    testWidgets('Cancel closes the sheet and saves nothing', (
      WidgetTester tester,
    ) async {
      await open(tester, apk);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });
}
