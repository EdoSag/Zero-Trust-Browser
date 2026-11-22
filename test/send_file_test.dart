import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';

class _FakeData extends BrowserData {
  _FakeData(super.ref);

  final List<(String, Uint8List, String, String)> sent =
      <(String, Uint8List, String, String)>[];
  final List<String> dismissed = <String>[];

  @override
  Future<void> sendFile(
    DeviceTabs to,
    Uint8List bytes, {
    required String name,
    required String mime,
  }) async => sent.add((to.deviceId, bytes, name, mime));

  @override
  Future<Uint8List> readSentFile(SentFile f) async =>
      Uint8List.fromList(<int>[7, 7, 7]);

  @override
  Future<void> dismissSentFile(SentFile f) async => dismissed.add(f.id);
}

/// B40: send a download to ZT Notes or to another device, and save what
/// other devices sent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/send_engine');
  late List<MethodCall> calls;
  late Object? notesAnswer;
  late int fileBytes;

  final SentFile incoming = SentFile(
    id: 's1',
    file: ZtAttachmentRef(
      id: '0123456789abcdef0123456789abcdef',
      key: Uint8List(32),
      size: 3,
      mimeType: 'application/pdf',
      name: 'ticket.pdf',
    ),
    fromDevice: 'tablet-id',
    fromName: 'Pixel Tablet',
    toDevice: 'me',
    sentAt: DateTime(2026, 11, 22, 10),
  );

  setUp(() {
    calls = <MethodCall>[];
    notesAnswer = 'opened';
    fileBytes = 5000;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          switch (call.method) {
            case 'downloads':
              return <Map<String, Object?>>[
                <String, Object?>{
                  'key': 'k1',
                  'name': 'menu.jpg',
                  'mime': 'image/jpeg',
                  'time': DateTime.now().millisecondsSinceEpoch,
                  'status': 'done',
                  'bytes': fileBytes,
                  'total': fileBytes,
                },
              ];
            case 'sendDownloadTo':
              return notesAnswer;
            case 'downloadBytes':
              return Uint8List.fromList(<int>[1, 2, 3]);
            case 'saveBytesToDownloads':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a sent file keeps its encrypted file reference', () {
    final SentFile back = SentFile.fromJson(
      's1',
      incoming.toJson(),
      DateTime(2026),
    );
    expect(back.file.id, incoming.file.id);
    expect(back.file.key, incoming.file.key);
    expect(back.name, 'ticket.pdf');
    expect(back.mime, 'application/pdf');
    expect(back.fromName, 'Pixel Tablet');
    expect(back.toDevice, 'me');
    expect(back.sentAt, incoming.sentAt);
  });

  Future<_FakeData> pump(
    WidgetTester tester, {
    List<SentFile> received = const <SentFile>[],
    String locale = 'en',
  }) async {
    late _FakeData data;
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
          browserDataProvider.overrideWith((Ref ref) => data = _FakeData(ref)),
          sentFilesToMeProvider.overrideWith(
            (Ref ref) => Stream<List<SentFile>>.value(received),
          ),
          otherDevicesProvider.overrideWith(
            (Ref ref) => Stream<List<DeviceTabs>>.value(<DeviceTabs>[
              DeviceTabs(
                deviceId: 'laptop-id',
                deviceName: 'Work laptop',
                tabs: const <SavedTab>[],
                updatedAt: DateTime.now(),
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          theme: ZtTheme.dark(accent: const Color(0xFFF97316)),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const DownloadsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Built lazily: read it once so it exists.
    ProviderScope.containerOf(
      tester.element(find.byType(DownloadsPage)),
    ).read(browserDataProvider);
    return data;
  }

  Future<void> openSend(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send to…'));
    await tester.pumpAndSettle();
  }

  testWidgets('to ZT Notes: straight to that app', (tester) async {
    await pump(tester);
    await openSend(tester);
    expect(find.text('Send menu.jpg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('send-to-notes')));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((MethodCall c) => c.method == 'sendDownloadTo').arguments,
      <String, Object?>{'key': 'k1', 'package': 'dev.sagron.zerotrustnotes'},
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('ZT Notes missing or refusing the file says so', (tester) async {
    notesAnswer = 'notInstalled';
    await pump(tester);
    await openSend(tester);
    await tester.tap(find.byKey(const ValueKey<String>('send-to-notes')));
    await tester.pumpAndSettle();
    expect(find.text("ZT Notes isn't on this phone"), findsOneWidget);
    notesAnswer = 'unsupported';
    await openSend(tester);
    await tester.tap(find.byKey(const ValueKey<String>('send-to-notes')));
    await tester.pumpAndSettle();
    expect(
      find.text("ZT Notes can't take this kind of file yet"),
      findsOneWidget,
    );
  });

  testWidgets('to another device: the bytes go as an encrypted file', (
    tester,
  ) async {
    final _FakeData data = await pump(tester);
    await openSend(tester);
    await tester.tap(find.text('Work laptop'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((MethodCall c) => c.method == 'downloadBytes').arguments,
      <String, Object?>{'key': 'k1', 'max': ZtAttachments.defaultMaxBytes},
    );
    expect(data.sent, hasLength(1));
    expect(data.sent.single.$1, 'laptop-id');
    expect(data.sent.single.$2, <int>[1, 2, 3]);
    expect(data.sent.single.$3, 'menu.jpg');
    expect(data.sent.single.$4, 'image/jpeg');
    expect(find.text('Sent menu.jpg to Work laptop'), findsOneWidget);
  });

  testWidgets('a file over 20 MB can only go to ZT Notes', (tester) async {
    fileBytes = 30 * 1000 * 1000;
    final _FakeData data = await pump(tester);
    await openSend(tester);
    expect(
      find.text("Files over 20 MB can't be sent to devices"),
      findsOneWidget,
    );
    await tester.tap(find.text('Work laptop'));
    await tester.pumpAndSettle();
    expect(data.sent, isEmpty);
    expect(calls.where((MethodCall c) => c.method == 'downloadBytes'), isEmpty);
  });

  testWidgets('a file from another device: save puts it in Downloads', (
    tester,
  ) async {
    final _FakeData data = await pump(tester, received: <SentFile>[incoming]);
    expect(find.text('Sent from your devices'), findsOneWidget);
    expect(find.text('From Pixel Tablet · 3 bytes'), findsOneWidget);
    // Above the downloads, on screen, with Save beside the name.
    expect(
      tester.getTopLeft(find.text('ticket.pdf')).dy,
      lessThan(tester.getTopLeft(find.text('menu.jpg')).dy),
    );
    final Rect save = tester.getRect(find.widgetWithText(TextButton, 'Save'));
    expect(save.right, lessThanOrEqualTo(412));
    expect(save.width, greaterThan(40));
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    final MethodCall saved = calls.lastWhere(
      (MethodCall c) => c.method == 'saveBytesToDownloads',
    );
    expect(saved.arguments, <String, Object?>{
      'name': 'ticket.pdf',
      'mime': 'application/pdf',
      'bytes': Uint8List.fromList(<int>[7, 7, 7]),
    });
    expect(data.dismissed, <String>['s1']);
    expect(find.text('Saved ticket.pdf to Downloads'), findsOneWidget);
  });

  testWidgets('in Hebrew the received file fits', (tester) async {
    await pump(tester, received: <SentFile>[incoming], locale: 'he');
    expect(tester.takeException(), isNull);
    final Rect save = tester.getRect(find.widgetWithText(TextButton, 'שמירה'));
    expect(save.left, greaterThanOrEqualTo(0));
  });
}
