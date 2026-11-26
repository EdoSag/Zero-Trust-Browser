import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/page_assist.dart';
import 'package:zerotrust_browser/browser/reader.dart';
import 'package:zerotrust_browser/l10n/generated/app_l10n_en.dart';
import 'package:zerotrust_browser/l10n/generated/app_l10n_he.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/page_assist_sheet.dart';
import 'package:zt_assist/testing.dart';
import 'package:zt_assist/zt_assist.dart';

final AppL10nEn l = AppL10nEn();

const String pageText =
    'Kitchen renovation\nWork starts in January and takes five weeks.';

void main() {
  group('what ZT Assist is given', () {
    test('the article as plain text, title first', () {
      const Article article = Article(
        title: 'Kitchen renovation',
        content:
            '<div><h2>Plan</h2><p>Work starts in <b>January</b> &amp; takes '
            'five weeks.</p><script>track()</script><ul><li>Tiles</li>'
            '<li>Cabinets</li></ul></div>',
      );
      expect(
        pageTextForAssist(article),
        'Kitchen renovation\nPlan\n'
        'Work starts in January & takes five weeks.\nTiles\nCabinets',
      );
    });

    test('a question is asked in its own language, from the page only', () {
      final String english = pageQuestionInstruction(
        '  When does\nthe work start? ',
      );
      expect(english, startsWith('Answer the question using only the text'));
      expect(english, contains('Question: When does the work start?'));
      expect(english, endsWith('The text:'));

      final String hebrew = pageQuestionInstruction('מתי מתחילה העבודה?');
      expect(hebrew, startsWith('ענה על השאלה לפי הטקסט'));
      expect(hebrew, contains('השאלה: מתי מתחילה העבודה?'));
      expect(hebrew, endsWith('הטקסט:'));
    });

    test('Hebrew is told from English by its letters', () {
      expect(mostlyHebrew('מה כתוב על ה-iPhone?'), isTrue);
      expect(mostlyHebrew('What is שלום?'), isFalse);
      expect(mostlyHebrew('123'), isFalse);
    });
  });

  group('the sheet', () {
    late ZtAssist before;

    setUp(() => before = ZtAssist.instance);
    tearDown(() => ZtAssist.instance = before);

    Future<void> pumpSheet(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
      VoidCallback? onActivity,
    }) async {
      // A 1080x2400 phone, like the devices the app ships to.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          // The suite's real theme: its buttons are as wide as they are
          // allowed to be, which breaks rows a plain theme lets through.
          theme: ZtTheme.light(),
          locale: locale,
          supportedLocales: ZtLanguages.supported,
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            AppL10n.delegate,
            ...ZtLanguages.delegates,
          ],
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showPageAssistSheet(
                  context,
                  title: 'Kitchen renovation',
                  text: pageText,
                  onActivity: onActivity,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    const double screenWidth = 1080 / 2.625;
    final Finder summarize = find.byKey(const Key('assist_summarize'));
    final Finder question = find.byKey(const Key('assist_question'));
    final Finder send = find.byKey(const Key('assist_send'));
    final Finder answer = find.byKey(const Key('assist_answer'));

    /// The button is laid out, inside the screen.
    void expectOnScreen(WidgetTester tester, Finder button) {
      expect(button, findsOneWidget);
      final Rect rect = tester.getRect(button);
      expect(rect.width, greaterThan(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(screenWidth));
    }

    testWidgets('offers a summary and a question, in that order', (
      WidgetTester tester,
    ) async {
      ZtAssist.instance = FakeZtAssist();
      await pumpSheet(tester);

      expect(find.text(l.assistAsk), findsOneWidget);
      expect(find.text(l.assistPagePrivacy), findsOneWidget);
      expect(find.text('Kitchen renovation'), findsOneWidget);
      expect(find.text(l.assistSummarizePage), findsOneWidget);
      expect(
        tester.getTopLeft(question).dy,
        greaterThan(tester.getTopLeft(summarize).dy),
      );
      // Nothing to send yet.
      expect(tester.widget<IconButton>(send).onPressed, isNull);
      expectOnScreen(tester, send);
      expect(tester.takeException(), isNull);
    });

    testWidgets('summarizes the page and shows the answer as it is written', (
      WidgetTester tester,
    ) async {
      int touched = 0;
      final FakeZtAssist assist = FakeZtAssist(
        answer: (_) => <String>['Work starts', ' in January.'],
      );
      ZtAssist.instance = assist;
      await pumpSheet(tester, onActivity: () => touched++);
      await tester.tap(summarize);
      await tester.pumpAndSettle();

      expect(assist.requests.single.task, ZtAssistTask.summarize);
      expect(assist.requests.single.text, pageText);
      expect(find.text('Work starts in January.'), findsOneWidget);
      expect(touched, greaterThan(0));
      // What was asked, the answer, the caution, then the buttons, each
      // below the one before.
      final List<Finder> order = <Finder>[
        find.byKey(const Key('assist_asked')),
        answer,
        find.byKey(const Key('assist_check')),
        find.byKey(const Key('assist_copy')),
        find.byKey(const Key('assist_back')),
      ];
      double last = -1;
      for (final Finder f in order) {
        expect(f, findsOneWidget);
        final double y = tester.getTopLeft(f).dy;
        expect(y, greaterThan(last), reason: '$f');
        last = y;
      }
      expectOnScreen(tester, find.byKey(const Key('assist_copy')));
      expectOnScreen(tester, find.byKey(const Key('assist_back')));
      expect(find.byKey(const Key('assist_stop')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('asks the question about the page', (
      WidgetTester tester,
    ) async {
      final FakeZtAssist assist = FakeZtAssist(
        answer: (_) => <String>['In January.'],
      );
      ZtAssist.instance = assist;
      await pumpSheet(tester);
      await tester.enterText(question, 'When does the work start?');
      await tester.pump();
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);
      await tester.tap(send);
      await tester.pumpAndSettle();

      final ZtAssistRequest request = assist.requests.single;
      expect(request.task, ZtAssistTask.ask);
      expect(request.text, pageText);
      expect(
        request.instruction,
        contains('Question: When does the work start?'),
      );
      expect(find.text('When does the work start?'), findsOneWidget);
      expect(find.text('In January.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And another one, from the start.
      await tester.tap(find.byKey(const Key('assist_back')));
      await tester.pumpAndSettle();
      expect(summarize, findsOneWidget);
      expect(answer, findsNothing);
    });

    testWidgets('Stop ends the answer and keeps what was written', (
      WidgetTester tester,
    ) async {
      final Completer<void> gate = Completer<void>();
      int piece = 0;
      final FakeZtAssist assist = FakeZtAssist(
        answer: (_) => <String>['Work starts', ' in January.'],
        beforePiece: () async {
          if (piece++ > 0) await gate.future;
        },
      );
      ZtAssist.instance = assist;
      await pumpSheet(tester);
      await tester.tap(summarize);
      await tester.pump();
      await tester.pump();

      expect(find.text('Work starts'), findsOneWidget);
      final Finder stop = find.byKey(const Key('assist_stop'));
      expectOnScreen(tester, stop);
      await tester.tap(stop);
      await tester.pump();

      expect(assist.cancelled, 1);
      expect(find.text('Work starts'), findsOneWidget);
      expect(find.text(l.assistStoppedByUser), findsOneWidget);
      expect(stop, findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Work starts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says when only the beginning of a long page was read', (
      WidgetTester tester,
    ) async {
      ZtAssist.instance = FakeZtAssist(
        answer: (_) => <String>['A summary.'],
        done: const ZtAssistDone(truncated: true),
      );
      await pumpSheet(tester);
      await tester.tap(summarize);
      await tester.pumpAndSettle();
      expect(find.text(l.assistReadBeginning), findsOneWidget);
    });

    testWidgets('each failure is said in words', (WidgetTester tester) async {
      final FakeZtAssist assist = FakeZtAssist(answer: (_) => const <String>[]);
      ZtAssist.instance = assist;
      await pumpSheet(tester);
      for (final (ZtAssistError error, String words)
          in <(ZtAssistError, String)>[
            (ZtAssistError.noModel, l.assistNoModel),
            (ZtAssistError.needsUpdate, l.assistNeedsUpdate),
            (ZtAssistError.loadFailed, l.assistLoadFailed),
            (ZtAssistError.stopped, l.assistStopped),
            (ZtAssistError.failed, l.assistFailed),
            (ZtAssistError.notInstalled, l.assistNotInstalled),
          ]) {
        assist.error = error;
        await tester.tap(summarize);
        await tester.pumpAndSettle();
        expect(find.text(words), findsOneWidget, reason: '$error');
        // No answer: nothing to copy, and no caution about one.
        expect(find.byKey(const Key('assist_copy')), findsNothing);
        expect(find.byKey(const Key('assist_check')), findsNothing);
        expect(tester.takeException(), isNull, reason: '$error');
        await tester.tap(find.byKey(const Key('assist_back')));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('Copy puts the answer on the clipboard', (
      WidgetTester tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
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
      ZtAssist.instance = FakeZtAssist(
        answer: (_) => <String>[' Work starts in January.\n'],
      );
      await pumpSheet(tester);
      await tester.tap(summarize);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assist_copy')));
      await tester.pump();
      expect(copied, 'Work starts in January.');
    });

    testWidgets('leaving in the middle stops the model', (
      WidgetTester tester,
    ) async {
      final Completer<void> gate = Completer<void>();
      final FakeZtAssist assist = FakeZtAssist(beforePiece: () => gate.future);
      ZtAssist.instance = assist;
      await pumpSheet(tester);
      await tester.tap(summarize);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(assist.cancelled, 1);
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('in Hebrew everything fits and reads right to left', (
      WidgetTester tester,
    ) async {
      final AppL10nHe he = AppL10nHe();
      ZtAssist.instance = FakeZtAssist(
        answer: (_) => <String>['העבודה מתחילה בינואר.'],
      );
      await pumpSheet(tester, locale: ZtLanguages.hebrew);
      expect(find.text(he.assistSummarizePage), findsOneWidget);
      await tester.enterText(question, 'מתי מתחילה העבודה?');
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SelectableText>(answer).textDirection,
        TextDirection.rtl,
      );
      expect(find.text(he.assistCopyAnswer), findsOneWidget);
      expectOnScreen(tester, find.byKey(const Key('assist_copy')));
      expect(tester.takeException(), isNull);
    });
  });
}
