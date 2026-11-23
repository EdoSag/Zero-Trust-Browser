import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/download_check.dart';
import 'package:zerotrust_browser/browser/private_lock.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/download_sheet.dart';
import 'package:zerotrust_browser/pages/downloads_page.dart';

/// The download manager (B33-B35): the checks before a file is saved, the
/// "Save this file?" sheet, and pause, resume and private downloads on the
/// Downloads page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('download checks (B35)', () {
    Set<DownloadWarning> check(
      String name, {
      String mime = 'application/octet-stream',
      String url = 'https://example.com/f',
    }) => downloadWarnings(name: name, mime: mime, url: url);

    test('ordinary files raise nothing', () {
      expect(check('report.pdf', mime: 'application/pdf'), isEmpty);
      expect(check('photo.jpg', mime: 'image/jpeg'), isEmpty);
      expect(check('archive.zip'), isEmpty);
      expect(check('script.js', mime: 'text/javascript'), isEmpty);
    });

    test('apps and programs', () {
      expect(check('game.apk'), <DownloadWarning>{DownloadWarning.app});
      expect(
        check('x', mime: 'application/vnd.android.package-archive'),
        contains(DownloadWarning.app),
      );
      expect(check('setup.EXE'), <DownloadWarning>{DownloadWarning.program});
      expect(check('run.ps1'), <DownloadWarning>{DownloadWarning.program});
      expect(check('tool.jar'), <DownloadWarning>{DownloadWarning.program});
    });

    test('names that hide what the file is', () {
      expect(check('invoice.pdf.exe'), contains(DownloadWarning.disguised));
      expect(check('photo.jpg.apk'), contains(DownloadWarning.disguised));
      expect(check('photo.jpg      .apk'), contains(DownloadWarning.disguised));
      // "invoice\u202Efdp.exe" shows as "invoiceexe.pdf".
      expect(
        check('invoice\u202Efdp.exe'),
        containsAll(<DownloadWarning>[
          DownloadWarning.disguised,
          DownloadWarning.program,
        ]),
      );
      // The site says it's an app, the name says PDF.
      expect(
        check('manual.pdf', mime: 'application/vnd.android.package-archive'),
        containsAll(<DownloadWarning>[
          DownloadWarning.app,
          DownloadWarning.disguised,
        ]),
      );
      // A program named like one is not disguised.
      expect(check('setup.exe'), isNot(contains(DownloadWarning.disguised)));
      expect(
        check('backup.tar.gz'),
        isNot(contains(DownloadWarning.disguised)),
      );
    });

    test('plain http, except devices on this network', () {
      expect(check('a.pdf', url: 'http://example.com/a.pdf'), <DownloadWarning>{
        DownloadWarning.insecure,
      });
      expect(check('a.pdf', url: 'http://192.168.1.1/a.pdf'), isEmpty);
      expect(check('a.pdf', url: 'http://printer.local/a.pdf'), isEmpty);
      expect(check('a.pdf', url: 'http://10.0.0.5/a.pdf'), isEmpty);
      expect(check('a.pdf', url: 'blob:https://example.com/1'), isEmpty);
    });

    test('names are cleaned like the engine cleans them', () {
      // No folders: never a way out of Downloads.
      expect(cleanFileName('../../etc/passwd'), '_.._etc_passwd');
      expect(cleanFileName('a/b\\c:d*e?.txt'), 'a_b_c_d_e_.txt');
      expect(cleanFileName('invoice\u202Efdp.exe'), 'invoicefdp.exe');
      expect(cleanFileName('  .hidden'), 'hidden');
      expect(cleanFileName(''), 'download');
      expect(cleanFileName('tab\there.pdf'), 'tabhere.pdf');
      final String long = cleanFileName('${'a' * 200}.pdf');
      expect(long.length, 120);
      expect(long.endsWith('.pdf'), isTrue);
      expect(fileExtension('Report.PDF'), 'pdf');
      expect(fileExtension('README'), '');
    });

    test('ask before downloading is on unless turned off', () {
      final BrowserSettings empty = BrowserSettings.fromJson(
        'x',
        const <String, Object?>{},
        DateTime(2026),
      );
      expect(empty.askBeforeDownload, isTrue);
      final BrowserSettings off = BrowserSettings.fromJson(
        'x',
        empty.copyWith(askBeforeDownload: false).toJson(),
        DateTime(2026),
      );
      expect(off.askBeforeDownload, isFalse);
    });
  });

  group('Save this file? sheet (B35)', () {
    Future<DownloadChoice?> open(
      WidgetTester tester,
      DownloadRequest r, {
      String locale = 'en',
      Future<void> Function()? act,
    }) async {
      DownloadChoice? result;
      bool closed = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
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
      await act?.call();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      return result;
    }

    const DownloadRequest pdf = DownloadRequest(
      requestId: 7,
      name: 'report.pdf',
      mime: 'application/pdf',
      size: 2500000,
      url: 'https://files.example.com/report.pdf',
    );

    testWidgets('shows name, size and site; Save keeps a renamed name', (
      WidgetTester tester,
    ) async {
      final DownloadChoice? c = await open(
        tester,
        pdf,
        act: () async {
          expect(find.text('Save this file?'), findsOneWidget);
          expect(find.textContaining('2.5 MB'), findsOneWidget);
          expect(find.textContaining('from files.example.com'), findsOneWidget);
          expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
          // A normal tab has no private choice.
          expect(find.text('Keep private'), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey<String>('download-name')),
            'Q3/report.pdf',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        },
      );
      expect(c, isNotNull);
      expect(c!.name, 'Q3_report.pdf');
      expect(c.openWhenDone, isFalse);
    });

    testWidgets('Cancel saves nothing', (WidgetTester tester) async {
      final DownloadChoice? c = await open(
        tester,
        pdf,
        act: () => tester.tap(find.text('Cancel')),
      );
      expect(c, isNull);
    });

    testWidgets('an app warns and asks "Save anyway", in Hebrew too', (
      WidgetTester tester,
    ) async {
      final DownloadChoice? c = await open(
        tester,
        const DownloadRequest(
          requestId: 1,
          name: 'free-game.apk',
          mime: 'application/vnd.android.package-archive',
          size: -1,
          url: 'http://example.com/free-game.apk',
        ),
        locale: 'he',
        act: () async {
          expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
          expect(find.text('גודל לא ידוע', findRichText: true), findsNothing);
          expect(find.textContaining('גודל לא ידוע'), findsOneWidget);
          expect(find.widgetWithText(FilledButton, 'שמירה'), findsNothing);
          await tester.tap(find.text('לשמור בכל זאת'));
        },
      );
      expect(c?.name, 'free-game.apk');
    });

    testWidgets('from a private tab: keep private by default, or save to '
        'the phone', (WidgetTester tester) async {
      const DownloadRequest r = DownloadRequest(
        requestId: 2,
        name: 'ticket.pdf',
        mime: 'application/pdf',
        size: 1000,
        url: 'https://example.com/ticket.pdf',
        private: true,
      );
      final DownloadChoice? kept = await open(
        tester,
        r,
        act: () async {
          expect(
            find.text('Save this file from a private tab?'),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        },
      );
      expect(kept?.keepPrivate, isTrue);

      final DownloadChoice? phone = await open(
        tester,
        r,
        act: () async {
          await tester.tap(
            find.byKey(const ValueKey<String>('download-save-phone')),
          );
          await tester.pump();
          await tester.tap(find.text('Open when done'));
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        },
      );
      expect(phone?.keepPrivate, isFalse);
      expect(phone?.openWhenDone, isTrue);
    });

    test('request from the engine event', () {
      final DownloadRequest r = DownloadRequest.fromMap(<Object?, Object?>{
        'requestId': 3,
        'name': 'a.bin',
        'mime': 'application/octet-stream',
        'size': 12,
        'url': 'blob:https://app.example.com/123',
        'pageUrl': 'https://app.example.com/page',
        'private': true,
      });
      expect(r.requestId, 3);
      expect(r.private, isTrue);
      expect(r.site, 'app.example.com');
    });
  });

  group('Downloads page: pause, resume, private (B33, B34)', () {
    const MethodChannel channel = MethodChannel('test/download_manager');
    late List<MethodCall> calls;
    late List<Map<String, Object?>> files;

    setUp(() {
      calls = <MethodCall>[];
      files = <Map<String, Object?>>[
        <String, Object?>{
          'key': 'k-run',
          'name': 'movie.mp4',
          'mime': 'video/mp4',
          'time': 1763100000300,
          'status': 'running',
          'bytes': 1000000,
          'total': 4000000,
          'canPause': true,
        },
        <String, Object?>{
          'key': 'k-failed',
          'name': 'big.zip',
          'mime': 'application/zip',
          'time': 1763100000200,
          'status': 'failed',
          'error': 'network',
          'bytes': 10,
          'total': 100,
          'canResume': true,
        },
        <String, Object?>{
          'key': 'k-private',
          'name': 'ticket.pdf',
          'mime': 'application/pdf',
          'time': 1763100000100,
          'status': 'done',
          'bytes': 2048,
          'total': 2048,
          'private': true,
        },
      ];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            calls.add(call);
            switch (call.method) {
              case 'downloads':
                return files;
              case 'saveDownloadToPhone':
                return true;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            browserEngineProvider.overrideWithValue(BrowserEngine(channel)),
          ],
          child: MaterialApp(
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: const DownloadsPage(),
          ),
        ),
      );
      // A running download keeps the list polling: pump, don't settle.
      await tester.pump();
      await tester.pump();
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    testWidgets('private downloads first, under their own heading', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      expect(find.text('Private downloads'), findsOneWidget);
      final double heading = tester
          .getTopLeft(find.text('Private downloads'))
          .dy;
      final double ticket = tester.getTopLeft(find.text('ticket.pdf')).dy;
      final double movie = tester.getTopLeft(find.text('movie.mp4')).dy;
      expect(heading, lessThan(ticket));
      expect(ticket, lessThan(movie));
      await leave(tester);
    });

    testWidgets('locked private tabs hide their downloads until unlocked', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(DownloadsPage)),
      ).read(privateLockProvider.notifier).lock();
      await tester.pump();
      expect(find.text('ticket.pdf'), findsNothing);
      expect(
        find.text('Locked with your private tabs. Unlock to see them.'),
        findsOneWidget,
      );
      final Finder unlock = find.byKey(
        const ValueKey<String>('unlock-private-downloads'),
      );
      expect(unlock, findsOneWidget);
      // Normal downloads stay, below the locked heading.
      expect(
        tester.getTopLeft(find.text('Private downloads')).dy,
        lessThan(tester.getTopLeft(find.text('movie.mp4')).dy),
      );
      await leave(tester);
    });

    testWidgets('select all leaves out locked private downloads', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(DownloadsPage)),
      ).read(privateLockProvider.notifier).lock();
      await tester.pump();
      await tester.longPress(find.text('movie.mp4'));
      await tester.pump();
      await tester.tap(find.byTooltip('Select all'));
      await tester.pump();
      await tester.tap(find.byTooltip('Remove from list'));
      await tester.pump();
      final List<Object?> keys =
          (calls
                      .lastWhere(
                        (MethodCall c) => c.method == 'forgetDownloads',
                      )
                      .arguments
                  as Map<Object?, Object?>)['keys']!
              as List<Object?>;
      expect(keys, isNotEmpty);
      expect(keys, isNot(contains('k-private')));
      await leave(tester);
    });

    testWidgets('pause a running download, retry a failed one', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      expect(find.text('1.0 MB of 4.0 MB'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(
        calls
            .lastWhere((MethodCall c) => c.method == 'pauseDownload')
            .arguments,
        <String, Object?>{'key': 'k-run'},
      );
      await tester.tap(find.byTooltip('Try again'));
      await tester.pump();
      expect(
        calls
            .lastWhere((MethodCall c) => c.method == 'resumeDownload')
            .arguments,
        <String, Object?>{'key': 'k-failed'},
      );
      await leave(tester);
    });

    testWidgets('a private download can be saved to the phone', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('More').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Save to phone'));
      await tester.pump();
      await tester.pump();
      expect(
        calls
            .lastWhere((MethodCall c) => c.method == 'saveDownloadToPhone')
            .arguments,
        <String, Object?>{'key': 'k-private'},
      );
      expect(find.text('Saved ticket.pdf to Downloads'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('cancelling an unfinished download asks first', (
      WidgetTester tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.byTooltip('More').at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Open'), findsNothing);
      await tester.tap(find.text('Cancel download'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Cancel download?'), findsOneWidget);
      await leave(tester);
    });
  });
}
