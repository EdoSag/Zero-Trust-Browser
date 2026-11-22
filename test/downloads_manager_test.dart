import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';

/// B36 to B38: the Downloads page finds, groups, selects, renames and
/// forgets downloads, and the download rules travel with the settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('test/downloads_manager');
  late List<MethodCall> calls;
  late List<Map<String, Object?>> files;

  final DateTime now = DateTime.now();
  int at(int daysAgo, [int hour = 12]) => DateTime(
    now.year,
    now.month,
    now.day - daysAgo,
    hour,
  ).millisecondsSinceEpoch;

  Map<String, Object?> file(
    String key,
    String name,
    String mime,
    int time, {
    String status = 'done',
    bool private = false,
    String? url,
    String? error,
  }) => <String, Object?>{
    'key': key,
    'name': name,
    'mime': mime,
    'time': time,
    'status': status,
    'bytes': 1024 * 1024,
    'total': 1024 * 1024,
    'private': private,
    'canRename': status == 'done',
    'url': url,
    'error': error,
  };

  setUp(() {
    files = <Map<String, Object?>>[
      file(
        'a',
        'holiday.jpg',
        'image/jpeg',
        at(0, 14),
        url: 'https://pics.example/holiday.jpg',
      ),
      file('b', 'report.pdf', 'application/pdf', at(0, 9)),
      file('c', 'song.mp3', 'audio/mpeg', at(1)),
      file('d', 'backup.zip', 'application/zip', at(9)),
    ];
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          switch (call.method) {
            case 'downloads':
              return files;
            case 'forgetDownloads':
              final List<Object?> keys =
                  (call.arguments as Map<Object?, Object?>)['keys']!
                      as List<Object?>;
              files.removeWhere(
                (Map<String, Object?> f) => keys.contains(f['key']),
              );
              return null;
            case 'renameDownload':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pump(WidgetTester tester, {String locale = 'en'}) async {
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
          home: const DownloadsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MethodCall last(String method) =>
      calls.lastWhere((MethodCall c) => c.method == method);

  group('kinds and filters', () {
    test('a file is sorted by type, then by name', () {
      expect(downloadKind('image/png', 'x.png'), DownloadKind.images);
      expect(downloadKind('video/mp4', 'x.mp4'), DownloadKind.video);
      expect(downloadKind('audio/ogg', 'x.ogg'), DownloadKind.audio);
      expect(downloadKind('application/pdf', 'x.pdf'), DownloadKind.documents);
      expect(downloadKind('application/zip', 'x.zip'), DownloadKind.archives);
      expect(
        downloadKind('application/vnd.android.package-archive', 'x.apk'),
        DownloadKind.apps,
      );
      // Servers often say "octet-stream": the name decides.
      expect(
        downloadKind('application/octet-stream', 'notes.docx'),
        DownloadKind.documents,
      );
      expect(
        downloadKind('application/octet-stream', 'app.apk'),
        DownloadKind.apps,
      );
      expect(
        downloadKind('application/octet-stream', 'blob'),
        DownloadKind.other,
      );
    });

    test('search ignores case; kind and search combine', () {
      final List<DownloadItem> items = <DownloadItem>[
        for (final Map<String, Object?> f in files) DownloadItem.fromMap(f),
      ];
      expect(
        filterDownloads(items, query: 'REP').map((DownloadItem d) => d.key),
        <String>['b'],
      );
      expect(
        filterDownloads(
          items,
          kind: DownloadKind.images,
        ).map((DownloadItem d) => d.key),
        <String>['a'],
      );
      expect(
        filterDownloads(items, query: 'song', kind: DownloadKind.images),
        isEmpty,
      );
      expect(filterDownloads(items), hasLength(4));
    });

    test('items are grouped by their local day', () {
      expect(
        downloadDay(DateTime(2026, 11, 22, 23, 59)),
        downloadDay(DateTime(2026, 11, 22, 0, 1)),
      );
      expect(
        downloadDay(DateTime(2026, 11, 22, 0, 1)),
        isNot(downloadDay(DateTime(2026, 11, 21, 23, 59))),
      );
    });
  });

  testWidgets('day headings come above their files, in order', (tester) async {
    await pump(tester);
    final double today = tester.getTopLeft(find.text('Today')).dy;
    final double photo = tester.getTopLeft(find.text('holiday.jpg')).dy;
    final double pdf = tester.getTopLeft(find.text('report.pdf')).dy;
    final double yesterday = tester.getTopLeft(find.text('Yesterday')).dy;
    final double song = tester.getTopLeft(find.text('song.mp3')).dy;
    final double zip = tester.getTopLeft(find.text('backup.zip')).dy;
    expect(today, lessThan(photo));
    expect(photo, lessThan(pdf));
    expect(pdf, lessThan(yesterday));
    expect(yesterday, lessThan(song));
    expect(song, lessThan(zip));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('4 downloads · 4.2 MB on your phone'), findsOneWidget);
  });

  testWidgets('a kind chip shows only that kind', (tester) async {
    await pump(tester);
    final Finder chip = find.widgetWithText(FilterChip, 'Images');
    final Rect box = tester.getRect(chip);
    expect(box.width, greaterThan(40));
    expect(box.left, greaterThanOrEqualTo(0));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('holiday.jpg'), findsOneWidget);
    expect(find.text('report.pdf'), findsNothing);
    expect(find.text('song.mp3'), findsNothing);
  });

  testWidgets('search finds files by name', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Search downloads'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zip');
    await tester.pumpAndSettle();
    expect(find.text('backup.zip'), findsOneWidget);
    expect(find.text('holiday.jpg'), findsNothing);
    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('No downloads match'), findsOneWidget);
  });

  testWidgets('long press selects; remove from list keeps the files', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('song.mp3'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    // A tap while selecting selects; it doesn't open.
    expect(calls.where((MethodCall c) => c.method == 'openDownload'), isEmpty);
    await tester.tap(find.byTooltip('Remove from list'));
    await tester.pumpAndSettle();
    final List<Object?> keys =
        (last('forgetDownloads').arguments as Map<Object?, Object?>)['keys']!
            as List<Object?>;
    expect(keys.toSet(), <String>{'b', 'c'});
    expect(
      calls.where((MethodCall c) => c.method == 'deleteDownload'),
      isEmpty,
    );
    expect(find.text('report.pdf'), findsNothing);
    expect(find.text('holiday.jpg'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('select all, then delete asks once and deletes each', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('report.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('4 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 4 files?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      calls
          .where((MethodCall c) => c.method == 'deleteDownload')
          .map((MethodCall c) => (c.arguments as Map<Object?, Object?>)['key'])
          .toSet(),
      <String>{'a', 'b', 'c', 'd'},
    );
  });

  testWidgets('clear list keeps private and unfinished downloads', (
    tester,
  ) async {
    files.add(file('p', 'secret.pdf', 'application/pdf', at(0), private: true));
    files.add(
      file(
        'r',
        'big.iso',
        'application/octet-stream',
        at(0),
        status: 'running',
      ),
    );
    await pump(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear list (keep files)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    final List<Object?> keys =
        (last('forgetDownloads').arguments as Map<Object?, Object?>)['keys']!
            as List<Object?>;
    expect(keys.toSet(), <String>{'a', 'b', 'c', 'd'});
  });

  testWidgets('rename and copy link from the item menu', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'beach.jpg');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(last('renameDownload').arguments, <String, Object?>{
      'key': 'a',
      'name': 'beach.jpg',
    });

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall c) async {
        if (c.method == 'Clipboard.setData') {
          copied = (c.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, 'https://pics.example/holiday.jpg');
    // Only files with a link offer it.
    await tester.tap(find.byTooltip('More').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsNothing);
  });

  testWidgets('a download waiting for Wi-Fi says so', (tester) async {
    files.insert(
      0,
      file(
        'w',
        'movie.mp4',
        'video/mp4',
        at(0, 20),
        status: 'waiting',
        error: 'wifi',
      ),
    );
    await pump(tester);
    expect(find.text('Waiting for Wi-Fi'), findsOneWidget);
  });

  testWidgets('in Hebrew the page lays out without overflow', (tester) async {
    await pump(tester, locale: 'he');
    expect(tester.takeException(), isNull);
    final Rect chip = tester.getRect(find.widgetWithText(FilterChip, 'תמונות'));
    expect(chip.right, lessThanOrEqualTo(412));
    await tester.longPress(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('1 נבחרו'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('download rules in the settings', () {
    test('defaults: any network, three at once, files kept', () {
      const BrowserSettings s = BrowserSettings();
      expect(s.downloadWifiOnly, isFalse);
      expect(s.downloadsAtOnce, 3);
      expect(s.autoDeleteDownloadsDays, 0);
    });

    test('round trip, and a bad count from another device is clamped', () {
      final BrowserSettings s = const BrowserSettings().copyWith(
        downloadWifiOnly: true,
        downloadsAtOnce: 1,
        autoDeleteDownloadsDays: 30,
      );
      final BrowserSettings back = BrowserSettings.fromJson(
        's',
        s.toJson(),
        DateTime(2026),
      );
      expect(back.downloadWifiOnly, isTrue);
      expect(back.downloadsAtOnce, 1);
      expect(back.autoDeleteDownloadsDays, 30);
      final Map<String, Object?> json = s.toJson()..['downloadsAtOnce'] = 40;
      expect(
        BrowserSettings.fromJson('s', json, DateTime(2026)).downloadsAtOnce,
        5,
      );
      // Settings saved before B38 have none of these.
      final Map<String, Object?> old = const BrowserSettings().toJson()
        ..remove('downloadWifiOnly')
        ..remove('downloadsAtOnce')
        ..remove('autoDeleteDownloadsDays');
      final BrowserSettings fromOld = BrowserSettings.fromJson(
        's',
        old,
        DateTime(2026),
      );
      expect(fromOld.downloadsAtOnce, 3);
      expect(fromOld.autoDeleteDownloadsDays, 0);
    });
  });
}
