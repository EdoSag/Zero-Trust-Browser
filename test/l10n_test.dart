import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/shortcuts_page.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';

Map<String, Object?> arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, Object?>;

void main() {
  test('every text has a Hebrew translation with the same placeholders', () {
    final Map<String, Object?> en = arb('app_en.arb');
    final Map<String, Object?> he = arb('app_he.arb');
    final RegExp hebrew = RegExp('[֐-׿]');
    final RegExp slot = RegExp(r'\{(\w+)[,}]');
    for (final String key in en.keys) {
      if (key.startsWith('@')) continue;
      final String? text = he[key] as String?;
      expect(text, isNotNull, reason: '$key has no Hebrew text');
      Set<String> slots(String s) =>
          <String>{for (final RegExpMatch m in slot.allMatches(s)) m.group(1)!}
            ..removeAll(<String>{'other', 'one', 'two', 'many'});
      expect(
        slots(text!),
        slots(en[key]! as String),
        reason: '$key placeholders differ',
      );
      // Brand names, units and pure placeholders may stay as they are.
      final String bare = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
      if (RegExp('[A-Za-z]{4,}').hasMatch(bare) && !hebrew.hasMatch(bare)) {
        fail('$key looks untranslated: $text');
      }
    }
    expect(
      he.keys.where((String k) => !k.startsWith('@') && !en.containsKey(k)),
      isEmpty,
    );
  });

  test('labels and lists read right in both languages', () async {
    final AppL10n en = await AppL10n.delegate.load(const Locale('en'));
    final AppL10n he = await AppL10n.delegate.load(const Locale('he'));
    const List<String> two = <String>[
      SitePermission.camera,
      SitePermission.microphone,
    ];
    expect(en.permissionPhrase(two), 'camera and microphone');
    expect(he.permissionPhrase(two), 'מצלמה ומיקרופון');
    expect(
      en.permissionPhrase(<String>[...two, SitePermission.location]),
      'camera, microphone and location',
    );
    expect(en.historyLabel(null), isNot(en.historyLabel(0)));
    expect(he.closeTabsLabel(7), isNot(en.closeTabsLabel(7)));
    expect(en.nTabs(1), '1 tab');
    expect(en.nTabs(3), '3 tabs');
    expect(he.nTabs(1), 'כרטיסייה אחת');
    expect(en.fileSize(1500000), '1.5 MB');
  });

  Widget app(Locale locale) => ProviderScope(
    overrides: [
      browserSettingsProvider.overrideWithValue(
        const BrowserSettings(
          shortcuts: <Shortcut>[
            Shortcut(url: 'https://example.com/news', title: 'חדשות'),
          ],
        ),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: const ShortcutsPage(),
    ),
  );

  testWidgets('in Hebrew the screen is mirrored and addresses stay readable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const Locale('he')));
    await tester.pumpAndSettle();
    expect(find.text('קיצורי דרך'), findsOneWidget);
    expect(find.text('Shortcuts'), findsNothing);

    final Finder title = find.text('חדשות');
    final Finder address = find.byType(AddressText);
    final Finder remove = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(IconButton),
    );
    final double width = tester.getSize(find.byType(Scaffold)).width;
    // Text on the right, the row's button on the left.
    expect(tester.getTopRight(title).dx, greaterThan(width / 2));
    expect(tester.getCenter(remove.first).dx, lessThan(width / 2));
    // The address keeps left-to-right order and never covers the title.
    final Text shown = tester.widget<Text>(
      find.descendant(of: address, matching: find.byType(Text)),
    );
    expect(shown.textDirection, TextDirection.ltr);
    expect(shown.textAlign, TextAlign.right);
    expect(shown.data, 'example.com/news');
    expect(
      tester.getTopLeft(address).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(title).dy - 1),
    );
  });

  testWidgets('in English the same screen runs left to right', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Shortcuts'), findsOneWidget);
    final double width = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getTopLeft(find.text('חדשות')).dx, lessThan(width / 2));
    final Finder remove = find.descendant(
      of: find.byType(ListTile),
      matching: find.byType(IconButton),
    );
    expect(tester.getCenter(remove.first).dx, greaterThan(width / 2));
  });
}
