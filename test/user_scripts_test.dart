import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/user_script.dart';
import 'package:zerotrust_browser/browser/user_scripts.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/pages/scripts_page.dart';

const String darkMode = '''
// ==UserScript==
// @name         Dark Example
// @name:he      אתר כהה
// @namespace    https://greasyfork.org/users/1
// @version      1.2.10
// @description  Makes example.com dark
// @author       Someone
// @match        https://*.example.com/*
// @match        *://news.example.org/articles/*
// @exclude      *://*.example.com/login*
// @require      https://cdn.example.net/lib.js
// @resource     css https://cdn.example.net/style.css
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_xmlhttpRequest
// @grant        GM_download
// @connect      api.example.net
// @run-at       document-start
// @noframes
// @updateURL    https://greasyfork.org/scripts/1/code/dark.meta.js
// ==/UserScript==

document.documentElement.style.background = '#000';
''';

void main() {
  group('metadata', () {
    final UserScriptMeta m = UserScriptMeta.parse(darkMode)!;

    test('reads the block', () {
      expect(m.name, 'Dark Example');
      expect(m.nameIn('he'), 'אתר כהה');
      expect(m.nameIn('fr'), 'Dark Example');
      expect(m.version, '1.2.10');
      expect(m.author, 'Someone');
      expect(m.matches, hasLength(2));
      expect(m.requires, <String>['https://cdn.example.net/lib.js']);
      expect(m.resources, <String, String>{
        'css': 'https://cdn.example.net/style.css',
      });
      expect(m.runAt, 'document-start');
      expect(m.noFrames, isTrue);
      expect(m.updateUrl, endsWith('dark.meta.js'));
    });

    test('names what it can do and what is missing', () {
      expect(m.permissions, <ScriptPermission>{
        ScriptPermission.storage,
        ScriptPermission.network,
      });
      expect(m.unsupportedGrants, <String>['GM_download']);
      expect(m.connectSites, <String>['api.example.net']);
      expect(m.sites, <String>['*.example.com', 'news.example.org']);
    });

    test('no block, or no name, is not a script', () {
      expect(UserScriptMeta.parse('alert(1)'), isNull);
      expect(
        UserScriptMeta.parse(
          '// ==UserScript==\n// @match *://*/*\n// ==/UserScript==',
        ),
        isNull,
      );
    });

    test('runs where it says, and nowhere else', () {
      expect(m.runsOn('https://example.com/page'), isTrue);
      expect(m.runsOn('https://www.example.com/page?q=1#top'), isTrue);
      expect(m.runsOn('http://www.example.com/page'), isFalse);
      expect(m.runsOn('https://www.example.com/login?next=1'), isFalse);
      expect(m.runsOn('https://notexample.com/'), isFalse);
      expect(m.runsOn('https://example.com.evil.net/'), isFalse);
      expect(m.runsOn('http://news.example.org/articles/1'), isTrue);
      expect(m.runsOn('https://news.example.org/other'), isFalse);
    });

    test('a script without site rules runs everywhere, and says so', () {
      final UserScriptMeta all = UserScriptMeta.parse(
        '// ==UserScript==\n// @name All\n// ==/UserScript==',
      )!;
      expect(all.sites, isNull);
      expect(all.runsOn('https://anything.net/'), isTrue);
      expect(all.runAt, 'document-idle');
      expect(all.connectSites, isEmpty);
    });

    test('network without @connect means any site', () {
      final UserScriptMeta any = UserScriptMeta.parse(
        '// ==UserScript==\n// @name N\n// @match https://a.com/*\n'
        '// @grant GM.xmlHttpRequest\n// ==/UserScript==',
      )!;
      expect(any.usesNetwork, isTrue);
      expect(any.connectSites, isNull);
    });
  });

  group('site rules', () {
    test('match patterns', () {
      expect(matchPatternRule('<all_urls>')!.test('https://x.org/'), isTrue);
      final UrlRule r = matchPatternRule('*://*.google.com/search*')!;
      expect(r.test('https://www.google.com/search?q=a'), isTrue);
      expect(r.test('https://google.com/search'), isTrue);
      expect(r.test('https://google.com:8443/search'), isTrue);
      expect(r.test('https://google.com/maps'), isFalse);
      expect(r.test('https://google.com.evil.org/search'), isFalse);
      expect(matchPatternRule('https://www.*.com/*'), isNull);
      expect(matchPatternRule('not a pattern'), isNull);
    });

    test('globs and regular expressions', () {
      expect(globRule('*')!.test('https://a.b/'), isTrue);
      final UrlRule g = globRule('http*://*.wikipedia.org/wiki/*')!;
      expect(g.test('https://en.wikipedia.org/wiki/Cat'), isTrue);
      expect(g.test('https://en.wikipedia.org/w/index.php'), isFalse);
      final UrlRule tld = globRule('https://www.amazon.tld/*')!;
      expect(tld.test('https://www.amazon.de/x'), isTrue);
      expect(tld.test('https://www.amazon.co.uk/x'), isTrue);
      final UrlRule re = globRule(r'/^https:\/\/(www\.)?youtube\.com\//')!;
      expect(re.ignoreCase, isTrue);
      expect(re.test('https://youtube.com/watch'), isTrue);
      expect(globRule('/[unclosed/'), isNull);
    });

    test('sites as people read them', () {
      expect(hostOfPattern('*://*/*'), isNull);
      expect(hostOfPattern('<all_urls>'), isNull);
      expect(hostOfPattern('https://*.reddit.com/*'), '*.reddit.com');
      expect(hostOfPattern('*example.com*'), '*.example.com');
      expect(
        hostOfPattern(r'/^https?:\/\/www\.youtube\.com\//'),
        'www.youtube.com',
      );
      expect(hostOfPattern('http*://*.*/*'), isNull);
    });

    test('version order', () {
      expect(compareVersions('1.2.9', '1.2.10'), lessThan(0));
      expect(compareVersions('2.0', '2.0.0'), 0);
      expect(compareVersions('2024.1.5', '2023.12.31'), greaterThan(0));
      expect(compareVersions(null, '1'), lessThan(0));
    });
  });

  group('stored script', () {
    final UserScript s = UserScript(
      id: 'abc',
      code: darkMode,
      installedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      sourceUrl: 'https://greasyfork.org/scripts/1/code/dark.user.js',
      requires: const <String, String>{
        'https://cdn.example.net/lib.js': 'var lib = 1;',
      },
      resources: const <String, ScriptResource>{
        'css': ScriptResource(
          url: 'https://cdn.example.net/style.css',
          mime: 'text/css',
          data: 'Ym9keXt9',
        ),
      },
    );

    test('round-trips through the synced store, off in private tabs', () {
      final UserScript back = UserScript.fromJson(
        'abc',
        jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
        DateTime.now(),
      );
      expect(back.code, darkMode);
      expect(back.enabled, isTrue);
      expect(back.allowPrivate, isFalse);
      expect(back.requires, s.requires);
      expect(back.resources['css']!.mime, 'text/css');
      expect(back.updateUrl, endsWith('dark.meta.js'));
    });

    test('the engine gets enabled scripts, with their files first', () {
      final List<Map<String, Object?>> out = toEngine(<UserScript>[
        s,
        s.copyWith(enabled: false),
      ]);
      expect(out, hasLength(1));
      final String code = out.first['code']! as String;
      expect(
        code.indexOf('var lib = 1;'),
        lessThan(code.indexOf('==UserScript==')),
      );
      expect(out.first['allowPrivate'], isFalse);
      final Map<String, Object?> config =
          jsonDecode(out.first['config']! as String) as Map<String, Object?>;
      expect(config['runAt'], 'document-start');
      expect(config['noframes'], isTrue);
      expect((config['inc']! as List<Object?>), hasLength(2));
      expect((config['exc']! as List<Object?>), hasLength(1));
      expect(
        ((config['info']! as Map<String, Object?>)['scriptMetaStr']! as String)
            .startsWith('// ==UserScript=='),
        isTrue,
      );
    });

    test('an update shows what is new', () {
      final String next = darkMode
          .replaceFirst('1.2.10', '1.3')
          .replaceFirst(
            '// @noframes',
            '// @noframes\n// @match https://shop.example.net/*\n// @grant GM_openInTab',
          );
      final PreparedScript p = PreparedScript(
        code: next,
        meta: UserScriptMeta.parse(next)!,
        requires: s.requires,
        resources: s.resources,
        existing: s,
      );
      expect(p.newSites, <String>['shop.example.net']);
      expect(p.newPermissions, <ScriptPermission>{ScriptPermission.tabs});
      expect(p.newlyEverywhere, isFalse);
    });
  });

  testWidgets(
    'the install screen warns before the sites, Install at the bottom',
    (WidgetTester tester) async {
      final UserScriptMeta meta = UserScriptMeta.parse(darkMode)!;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('he'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: ScriptInstallPage(
              load: (_) async => PreparedScript(
                code: darkMode,
                meta: meta,
                requires: const <String, String>{},
                resources: const <String, ScriptResource>{},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final AppL10n l = await AppL10n.delegate.load(const Locale('he'));
      expect(find.text('אתר כהה'), findsOneWidget);
      final Finder warning = find.text(l.scriptWarning);
      final Finder runsOn = find.text(l.scriptRunsOn);
      final Finder site = find.text('*.example.com');
      final Finder install = find.text(l.installScript);
      expect(warning, findsOneWidget);
      expect(
        tester.getTopLeft(warning).dy,
        lessThan(tester.getTopLeft(runsOn).dy),
      );
      expect(
        tester.getTopLeft(runsOn).dy,
        lessThan(tester.getTopLeft(site).dy),
      );
      // The address reads left to right, on the right side in Hebrew.
      final double width = tester.getSize(find.byType(Scaffold)).width;
      expect(tester.getTopRight(site).dx, greaterThan(width / 2));
      expect(tester.widget<Text>(site).textDirection, TextDirection.ltr);
      // Install sits at the bottom, on the left in Hebrew (Cancel on the right).
      final double height = tester.getSize(find.byType(Scaffold)).height;
      expect(tester.getCenter(install).dy, greaterThan(height * 0.8));
      expect(
        tester.getCenter(install).dx,
        lessThan(tester.getCenter(find.text(l.cancel).last).dx),
      );
    },
  );
}
