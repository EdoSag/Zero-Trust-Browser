import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';

/// The Downloads page against a fake engine: what it asks the engine for,
/// and what the person sees when the engine can't open or share a file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/downloads_engine');
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> answers;

  late List<Map<String, Object?>> files;
  List<Map<String, Object?>> oneFile() => <Map<String, Object?>>[
    <String, Object?>{
      'key': 'k-pdf',
      'name': 'report.pdf',
      'mime': 'application/pdf',
      'time': 1763100000000,
      'status': 'done',
      'bytes': 2048,
      'total': 2048,
    },
  ];

  setUp(() {
    files = oneFile();
    calls = <MethodCall>[];
    answers = <String, Object? Function(MethodCall)>{'downloads': (_) => files};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          final Object? Function(MethodCall)? a = answers[call.method];
          return a?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpPage(WidgetTester tester, {String locale = 'en'}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const DownloadsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> methods() => calls.map((MethodCall c) => c.method).toList();

  testWidgets('tapping a file asks the engine to open that file', (
    WidgetTester tester,
  ) async {
    answers['openDownload'] = (_) => 'opened';
    await pumpPage(tester);
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    final MethodCall open = calls.lastWhere(
      (MethodCall c) => c.method == 'openDownload',
    );
    expect(open.arguments, <String, Object?>{'key': 'k-pdf'});
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an engine error when opening shows a message, not nothing', (
    WidgetTester tester,
  ) async {
    // Before the fix Android refused to pass the file on and the tap
    // ended in an unhandled error: nothing happened on screen.
    answers['openDownload'] = (_) =>
        throw PlatformException(code: 'error', message: 'SecurityException');
    await pumpPage(tester);
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    expect(find.text("Couldn't open this file"), findsOneWidget);
  });

  testWidgets('no app for the file offers the Files app, which opens', (
    WidgetTester tester,
  ) async {
    answers['openDownload'] = (_) => 'noApp';
    answers['showDownloadsFolder'] = (_) => true;
    await pumpPage(tester);
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(
      find.text('No app on this phone opens this kind of file'),
      findsOneWidget,
    );
    // The action sits inside the snackbar, at the bottom of the screen.
    final Finder action = find.widgetWithText(SnackBarAction, 'Show in Files');
    expect(
      find.descendant(of: find.byType(SnackBar), matching: action),
      findsOneWidget,
    );
    expect(
      tester.getCenter(action).dy,
      greaterThan(tester.getSize(find.byType(Scaffold)).height / 2),
    );
    await tester.tap(action);
    await tester.pump();
    expect(methods(), contains('showDownloadsFolder'));
  });

  testWidgets('a file deleted elsewhere says so and reloads the list', (
    WidgetTester tester,
  ) async {
    answers['openDownload'] = (_) => 'missing';
    await pumpPage(tester);
    final int listsBefore = methods()
        .where((String m) => m == 'downloads')
        .length;
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    expect(find.text("This file isn't on the phone any more"), findsOneWidget);
    expect(
      methods().where((String m) => m == 'downloads').length,
      listsBefore + 1,
    );
  });

  testWidgets('Share from the menu shares that file; failure is shown', (
    WidgetTester tester,
  ) async {
    answers['shareDownload'] = (_) => 'failed';
    await pumpPage(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    final MethodCall share = calls.lastWhere(
      (MethodCall c) => c.method == 'shareDownload',
    );
    expect(share.arguments, <String, Object?>{'key': 'k-pdf'});
    expect(find.text("This file can't be shared"), findsOneWidget);
  });

  testWidgets('Delete asks first, then deletes that file and refreshes', (
    WidgetTester tester,
  ) async {
    answers['deleteDownload'] = (_) {
      files.clear();
      return null;
    };
    await pumpPage(tester, locale: 'he');
    await tester.tap(find.byTooltip('עוד'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('מחיקה').last);
    await tester.pumpAndSettle();
    expect(methods(), isNot(contains('deleteDownload')));
    await tester.tap(find.widgetWithText(FilledButton, 'מחיקה'));
    await tester.pumpAndSettle();
    final MethodCall del = calls.lastWhere(
      (MethodCall c) => c.method == 'deleteDownload',
    );
    expect(del.arguments, <String, Object?>{'key': 'k-pdf'});
    expect(find.text('report.pdf'), findsNothing);
  });

  test('engine answers map to results, old true/false too', () {
    expect(DownloadResult.parse('opened'), DownloadResult.done);
    expect(DownloadResult.parse(true), DownloadResult.done);
    expect(DownloadResult.parse('noApp'), DownloadResult.noApp);
    expect(DownloadResult.parse('missing'), DownloadResult.missing);
    expect(DownloadResult.parse(false), DownloadResult.failed);
    expect(DownloadResult.parse(null), DownloadResult.failed);
  });
}
