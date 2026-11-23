import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/engine/tab_view.dart';

/// Windows: the page is a native window that Dart places over TabView.
void main() {
  test('the place is in whole physical pixels', () {
    expect(
      windowsTabRect(const Offset(0, 56.4), const Size(400.2, 600), 1.5),
      const Rect.fromLTRB(0, 85, 600, 985),
    );
  });

  testWidgets('reports where the page goes, and hides it under a sheet', (
    WidgetTester tester,
  ) async {
    const MethodChannel channel = MethodChannel('zt_browser/engine');
    final List<Map<Object?, Object?>> bounds = <Map<Object?, Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      if (call.method == 'setTabBounds') {
        bounds.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('ZT')),
            body: const WindowsTabView(tabId: 't1'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(bounds.last, <Object?, Object?>{
      'tabId': 't1',
      'x': 0,
      'y': 112,
      'width': 1600,
      'height': 1088,
      'visible': true,
    });

    showModalBottomSheet<void>(
      context: tester.element(find.text('ZT')),
      builder: (_) => const Text('sheet'),
    );
    await tester.pumpAndSettle();
    expect(bounds.last['visible'], isFalse);
  });
}
