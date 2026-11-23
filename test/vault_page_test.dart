import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';
import 'package:zerotrust_browser/pages/vault_page.dart';

class _FakeUnlock extends VaultUnlock {
  _FakeUnlock({this.has = true});

  bool has;
  final List<bool> answers = <bool>[];
  int asked = 0;

  @override
  Future<bool> available() async => has;

  @override
  Future<bool> unlock(WidgetRef ref, String reason) async {
    asked++;
    return answers.isEmpty ? true : answers.removeAt(0);
  }
}

/// B39: the download vault opens only with the phone's lock, locks again
/// when the person leaves the app, and moves files in and out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/vault_engine');
  late List<MethodCall> calls;
  late List<Map<String, Object?>> vault;
  late Map<String, Object?> importAnswer;

  setUp(() {
    calls = <MethodCall>[];
    importAnswer = <String, Object?>{'added': 2, 'kept': 0};
    vault = <Map<String, Object?>>[
      <String, Object?>{
        'id': 'v1',
        'name': 'passport.pdf',
        'mime': 'application/pdf',
        'size': 300000,
        'time': DateTime(2026, 11, 20).millisecondsSinceEpoch,
      },
      <String, Object?>{
        'id': 'v2',
        'name': 'photo.jpg',
        'mime': 'image/jpeg',
        'size': 200000,
        'time': DateTime(2026, 11, 19).millisecondsSinceEpoch,
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>? ??
              const <Object?, Object?>{};
          switch (call.method) {
            case 'vaultList':
              return vault;
            case 'vaultOpen':
            case 'vaultShare':
              return 'opened';
            case 'vaultMoveToPhone':
              vault.removeWhere(
                (Map<String, Object?> v) => v['id'] == args['id'],
              );
              return true;
            case 'vaultDelete':
              vault.removeWhere(
                (Map<String, Object?> v) => v['id'] == args['id'],
              );
              return null;
            case 'vaultImport':
              return importAnswer;
            case 'vaultAddDownload':
              return true;
            case 'downloads':
              return <Map<String, Object?>>[
                <String, Object?>{
                  'key': 'k1',
                  'name': 'contract.pdf',
                  'mime': 'application/pdf',
                  'time': DateTime.now().millisecondsSinceEpoch,
                  'status': 'done',
                  'bytes': 5000,
                  'total': 5000,
                  'canRename': true,
                },
              ];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(
    WidgetTester tester,
    _FakeUnlock unlock, {
    String locale = 'en',
    Widget home = const VaultPage(),
  }) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
          vaultUnlockProvider.overrideWithValue(unlock),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> methods() => calls.map((MethodCall c) => c.method).toList();

  testWidgets('stays locked until the phone lock says yes', (tester) async {
    final _FakeUnlock unlock = _FakeUnlock()..answers.add(false);
    await pump(tester, unlock);
    expect(find.text('passport.pdf'), findsNothing);
    expect(methods(), isNot(contains('vaultList')));
    final Rect button = tester.getRect(
      find.byKey(const ValueKey<String>('unlock-vault')),
    );
    expect(button.width, greaterThan(80));
    expect(button.width, lessThan(412));
    await tester.tap(find.byKey(const ValueKey<String>('unlock-vault')));
    await tester.pumpAndSettle();
    expect(unlock.asked, 2);
    expect(find.text('passport.pdf'), findsOneWidget);
    expect(find.text('2 downloads · 500 KB on your phone'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('passport.pdf')).dy,
      lessThan(tester.getTopLeft(find.text('photo.jpg')).dy),
    );
  });

  testWidgets('no screen lock: opens, and says to set one', (tester) async {
    final _FakeUnlock unlock = _FakeUnlock(has: false);
    await pump(tester, unlock);
    expect(unlock.asked, 0);
    expect(find.text('passport.pdf'), findsOneWidget);
    expect(
      find.text('Set a screen lock on your phone so the vault asks for it.'),
      findsOneWidget,
    );
  });

  testWidgets('leaving the app locks it; opening a file does not', (
    tester,
  ) async {
    final _FakeUnlock unlock = _FakeUnlock();
    await pump(tester, unlock);
    await tester.tap(find.text('passport.pdf'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((MethodCall c) => c.method == 'vaultOpen').arguments,
      <String, Object?>{'id': 'v1'},
    );
    // The viewer app comes up: the vault stays open behind it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('passport.pdf'), findsOneWidget);
    // Now the person leaves on their own.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(methods(), contains('vaultClose'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('passport.pdf'), findsNothing);
    expect(find.byKey(const ValueKey<String>('unlock-vault')), findsOneWidget);
  });

  testWidgets('move to phone and delete from the menu', (tester) async {
    await pump(tester, _FakeUnlock());
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Move to phone's Downloads"));
    await tester.pumpAndSettle();
    expect(
      calls
          .lastWhere((MethodCall c) => c.method == 'vaultMoveToPhone')
          .arguments,
      <String, Object?>{'id': 'v1'},
    );
    expect(find.text('Moved passport.pdf to Downloads'), findsOneWidget);
    expect(find.text('passport.pdf'), findsNothing);

    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.text('photo.jpg is deleted from the vault for good.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(methods(), contains('vaultDelete'));
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('add from phone: move, and say what stayed', (tester) async {
    importAnswer = <String, Object?>{'added': 3, 'kept': 1};
    await pump(tester, _FakeUnlock());
    final Rect fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.right, lessThanOrEqualTo(412));
    expect(fab.bottom, lessThanOrEqualTo(915));
    await tester.tap(find.text('Add from phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((MethodCall c) => c.method == 'vaultImport').arguments,
      <String, Object?>{'move': true},
    );
    expect(
      find.text(
        "3 files added. The phone didn't let ZT Browser delete 1 original: "
        'delete them in the Files app.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a download moves into the vault from its menu', (tester) async {
    await pump(tester, _FakeUnlock(), home: const DownloadsPage());
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to vault'));
    await tester.pumpAndSettle();
    expect(
      calls
          .lastWhere((MethodCall c) => c.method == 'vaultAddDownload')
          .arguments,
      <String, Object?>{'key': 'k1'},
    );
    expect(find.text('contract.pdf is in the vault'), findsOneWidget);
    await tester.tap(find.text('Open vault'));
    await tester.pumpAndSettle();
    expect(find.text('Download vault'), findsOneWidget);
  });

  testWidgets('in Hebrew it fits and reads right to left', (tester) async {
    await pump(tester, _FakeUnlock(), locale: 'he');
    expect(tester.takeException(), isNull);
    final Rect name = tester.getRect(find.text('passport.pdf'));
    final Rect more = tester.getRect(find.byTooltip('עוד').first);
    // The menu button is on the left in Hebrew.
    expect(more.right, lessThan(name.left));
    expect(more.left, greaterThanOrEqualTo(0));
  });
}
