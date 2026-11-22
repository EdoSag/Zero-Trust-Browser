import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/widgets/tab_swipe.dart';

/// B28: swiping the browser's bars to switch tabs.
void main() {
  group('neighborTab', () {
    const List<String> ids = <String>['a', 'b', 'c'];

    test('moves one tab either way', () {
      expect(neighborTab(ids, 'b', 1), 'c');
      expect(neighborTab(ids, 'b', -1), 'a');
    });

    test('stops at both ends', () {
      expect(neighborTab(ids, 'c', 1), isNull);
      expect(neighborTab(ids, 'a', -1), isNull);
    });

    test('nothing for an unknown or missing tab', () {
      expect(neighborTab(ids, 'x', 1), isNull);
      expect(neighborTab(ids, null, 1), isNull);
      expect(neighborTab(const <String>[], 'a', 1), isNull);
    });
  });

  group('swipeStep', () {
    test('toward the start of the line is the next tab', () {
      expect(swipeStep(-50, TextDirection.ltr), 1);
      expect(swipeStep(50, TextDirection.ltr), -1);
    });

    test('mirrored in Hebrew', () {
      expect(swipeStep(50, TextDirection.rtl), 1);
      expect(swipeStep(-50, TextDirection.rtl), -1);
    });
  });

  group('TabSwipe', () {
    Future<List<Object>> pump(
      WidgetTester tester, {
      bool enabled = true,
      bool Function(int)? canSwitch,
      TextDirection direction = TextDirection.ltr,
    }) async {
      final List<Object> got = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
          home: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TabSwipe(
                  enabled: enabled,
                  canSwitch: canSwitch ?? (_) => true,
                  onSwitch: got.add,
                  onSwipeUp: () => got.add('up'),
                  child: Container(
                    key: const Key('bar'),
                    height: 56,
                    color: Colors.orange,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return got;
    }

    testWidgets('a long swipe left opens the next tab', (tester) async {
      final List<Object> got = await pump(tester);
      await tester.drag(find.byKey(const Key('bar')), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(got, <Object>[1]);
    });

    testWidgets('a long swipe right opens the tab before', (tester) async {
      final List<Object> got = await pump(tester);
      await tester.drag(find.byKey(const Key('bar')), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(got, <Object>[-1]);
    });

    testWidgets('in Hebrew a swipe right is the next tab', (tester) async {
      final List<Object> got = await pump(tester, direction: TextDirection.rtl);
      await tester.drag(find.byKey(const Key('bar')), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(got, <Object>[1]);
    });

    testWidgets('a short slow nudge does nothing', (tester) async {
      final List<Object> got = await pump(tester);
      await tester.timedDrag(
        find.byKey(const Key('bar')),
        const Offset(-30, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(got, isEmpty);
    });

    testWidgets('no tab that way: nothing, and the bar springs back', (
      tester,
    ) async {
      final List<Object> got = await pump(
        tester,
        canSwitch: (int step) => step < 0,
      );
      final Offset before = tester.getTopLeft(find.byKey(const Key('bar')));
      await tester.drag(find.byKey(const Key('bar')), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(got, isEmpty);
      expect(tester.getTopLeft(find.byKey(const Key('bar'))), before);
    });

    testWidgets('swiping up shows all tabs', (tester) async {
      final List<Object> got = await pump(tester);
      await tester.drag(find.byKey(const Key('bar')), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(got, <Object>['up']);
    });

    testWidgets('turned off: swipes do nothing', (tester) async {
      final List<Object> got = await pump(tester, enabled: false);
      await tester.drag(find.byKey(const Key('bar')), const Offset(-120, 0));
      await tester.drag(find.byKey(const Key('bar')), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(got, isEmpty);
    });
  });
}
