import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/identity.dart';
import 'package:zerotrust_browser/data/models.dart';

/// B42: the browser identity. An identity is one user agent string; the
/// tests here check that everything worked out from it tells the same
/// story, for every browser in the list and for strings a person types.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 20);

  IdentitySpec presetSpec(String id) => Identities.preset(id)!.spec(now);

  group('every browser in the list', () {
    for (final IdentityPreset p in Identities.presets) {
      test('${p.id}: header, Client Hints and navigator fields agree', () {
        final String ua = p.userAgent(now);
        final IdentitySpec s = p.spec(now);
        expect(s.userAgent, ua);
        expect(ua, startsWith('Mozilla/5.0 ('));
        // Only the phone's own versions are left for the engine to fill.
        expect(
          ua.replaceAll('{chrome}', '').replaceAll('{android}', ''),
          isNot(contains('{')),
        );
        expect(checkUserAgent(ua), isNull);
        expect(s.browser, isNot(IdentityBrowser.other));
        expect(s.system, isNot(IdentitySystem.other));

        // The system: in the user agent, in navigator.platform and in
        // Sec-CH-UA-Platform.
        final (String inUa, String? platform, String hint) = switch (s.system) {
          IdentitySystem.windows => ('Windows NT 10.0', 'Win32', 'Windows'),
          IdentitySystem.mac => ('Macintosh', 'MacIntel', 'macOS'),
          IdentitySystem.linux => ('X11; Linux', 'Linux x86_64', 'Linux'),
          IdentitySystem.iphone => ('iPhone', 'iPhone', 'iOS'),
          IdentitySystem.android => (
            'Android',
            s.browser == IdentityBrowser.firefox ? 'Linux aarch64' : null,
            'Android',
          ),
          _ => throw StateError('${s.system}'),
        };
        expect(ua, contains(inUa));
        expect(s.platform, platform);
        expect(s.hints.platform, hint);

        // Phone or not: "Mobile" in the user agent and Sec-CH-UA-Mobile.
        expect(s.mobile, ua.contains('Mobile'));
        expect(s.mobile, p.kind == IdentityKind.phone);
        expect(s.hints.formFactor, s.mobile ? 'Mobile' : 'Desktop');

        switch (s.browser) {
          case IdentityBrowser.chrome || IdentityBrowser.edge:
            // Chromium: real Client Hints, the engine's own navigator.
            expect(s.hasClientHints, isTrue);
            expect(
              s.hints.brand,
              s.browser == IdentityBrowser.edge
                  ? 'Microsoft Edge'
                  : 'Google Chrome',
            );
            expect(ua, contains('Chrome/{chrome}.0.0.0'));
            expect(s.hints.chromium, '{chrome}');
            expect(s.hints.brandVersion, '{chrome}');
            expect(s.vendor, isNull);
            expect(s.oscpu, isNull);
            expect(s.appVersion, isNull);
            expect(s.productSub, isNull);
            if (s.mobile) {
              // As Chrome on Android: no architecture, the phone's version.
              expect(s.hints.arch, '');
              expect(s.hints.bitness, 0);
              expect(s.hints.platformVersion, '{android}.0.0');
            } else {
              expect(
                s.hints.arch,
                s.system == IdentitySystem.mac ? 'arm' : 'x86',
              );
              expect(s.hints.bitness, 64);
              expect(s.hints.platformVersion, isNotEmpty);
              expect(s.hints.model, '');
            }
          case IdentityBrowser.firefox:
            expect(s.hasClientHints, isFalse);
            expect(s.vendor, '');
            expect(s.productSub, '20100101');
            expect(s.version, '${Identities.firefoxVersion(now)}');
            expect(ua, contains('rv:${s.version}.0'));
            expect(ua, endsWith('Firefox/${s.version}.0'));
            // oscpu is the part of the user agent that names the system.
            if (!s.mobile) expect(ua, contains(s.oscpu!));
            expect(s.appVersion, startsWith('5.0 ('));
          case IdentityBrowser.safari:
            expect(s.hasClientHints, isFalse);
            expect(s.vendor, 'Apple Computer, Inc.');
            expect(s.oscpu, isNull);
            expect(ua, contains('Version/${Identities.safariVersion(now)} '));
            // An iPhone and an iPad have a touch screen, a Mac has none.
            expect(s.touch, p.id == 'safari-mac' ? 0 : 5);
          default:
            fail('unexpected ${s.browser}');
        }
        // A Mac that reports touch points is taken for an iPad.
        if (s.system == IdentitySystem.mac && p.id != 'safari-ipad') {
          expect(s.touch, 0);
        }
      });
    }

    test('ids are unique, and "Desktop site" leads to a computer', () {
      final List<String> ids = <String>[
        for (final IdentityPreset p in Identities.presets) p.id,
      ];
      expect(ids.toSet().length, ids.length);
      for (final IdentityPreset p in Identities.presets) {
        if (p.kind == IdentityKind.phone) {
          final IdentityPreset desktop = Identities.preset(p.desktopId!)!;
          expect(desktop.kind, IdentityKind.computer);
          expect(desktop.spec(now).browser, p.spec(now).browser);
        } else {
          expect(p.desktopId, isNull);
        }
      }
    });

    test('Chrome on Windows, in full', () {
      expect(presetSpec('chrome-windows').toMap(), <String, Object?>{
        'id': 'chrome-windows',
        'ua':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/{chrome}.0.0.0 Safari/537.36',
        'hints': <String, Object?>{
          'brand': 'Google Chrome',
          'brandVersion': '{chrome}',
          'chromium': '{chrome}',
          'platform': 'Windows',
          'platformVersion': '19.0.0',
          'arch': 'x86',
          'bitness': 64,
          'model': '',
          'mobile': false,
          'formFactor': 'Desktop',
        },
        'platform': 'Win32',
      });
    });

    test('Firefox on Windows, in full', () {
      expect(presetSpec('firefox-windows').toMap(), <String, Object?>{
        'id': 'firefox-windows',
        'ua':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:157.0) '
            'Gecko/20100101 Firefox/157.0',
        'hints': <String, Object?>{
          'brand': null,
          'brandVersion': '',
          'chromium': '',
          'platform': 'Windows',
          'platformVersion': '',
          'arch': '',
          'bitness': 0,
          'model': '',
          'mobile': false,
          'formFactor': 'Desktop',
        },
        'platform': 'Win32',
        'vendor': '',
        'oscpu': 'Windows NT 10.0; Win64; x64',
        'appVersion': '5.0 (Windows)',
        'productSub': '20100101',
      });
    });

    test('Firefox on Android names the phone\'s Android version', () {
      final IdentitySpec s = presetSpec('firefox-android');
      expect(
        s.userAgent,
        'Mozilla/5.0 (Android {android}; Mobile; rv:157.0) '
        'Gecko/157.0 Firefox/157.0',
      );
      expect(s.appVersion, '5.0 (Android {android})');
      expect(s.oscpu, 'Linux aarch64');
    });

    test('an iPad says it is a Mac, with a touch screen', () {
      final IdentitySpec ipad = presetSpec('safari-ipad');
      final IdentitySpec mac = presetSpec('safari-mac');
      expect(ipad.userAgent, mac.userAgent);
      expect(ipad.platform, 'MacIntel');
      expect(ipad.touch, 5);
      expect(mac.touch, 0);
    });
  });

  group('a user agent someone typed', () {
    IdentitySpec of(String ua) => IdentitySpec.fromUserAgent('custom:x', ua);

    test('Chrome on a named Android phone', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UQ1A.240205.002) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.58 '
        'Mobile Safari/537.36',
      );
      expect(s.browser, IdentityBrowser.chrome);
      expect(s.system, IdentitySystem.android);
      expect(s.version, '130');
      expect(s.hints.brand, 'Google Chrome');
      expect(s.hints.chromium, '130');
      expect(s.hints.platform, 'Android');
      expect(s.hints.platformVersion, '14.0.0');
      expect(s.hints.model, 'Pixel 8');
      expect(s.hints.mobile, isTrue);
      expect(s.hints.formFactor, 'Mobile');
      // Nothing for a script to change: the engine is Chrome on Android.
      expect(s.platform, isNull);
      expect(s.vendor, isNull);
      expect(s.touch, isNull);
    });

    test('Chrome\'s shortened Android form keeps the model to itself', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      );
      expect(s.hints.model, '');
      expect(s.hints.platformVersion, '{android}.0.0');
    });

    test('an Android tablet is not a phone', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (Linux; Android 13; SM-X710) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      );
      expect(s.mobile, isFalse);
      expect(s.hints.formFactor, 'Tablet');
      expect(s.hints.model, 'SM-X710');
      expect(s.hints.platformVersion, '13.0.0');
    });

    test('Edge, Opera and Samsung Internet carry two versions', () {
      final IdentitySpec edge = of(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
      );
      expect(edge.browser, IdentityBrowser.edge);
      expect(edge.hints.brand, 'Microsoft Edge');

      final IdentitySpec opera = of(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 OPR/118.0.0.0',
      );
      expect(opera.browser, IdentityBrowser.opera);
      expect(opera.hints.brand, 'Opera');
      expect(opera.hints.brandVersion, '118');
      expect(opera.hints.chromium, '133');
      expect(opera.version, '118');

      final IdentitySpec samsung = of(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) SamsungBrowser/28.0 Chrome/130.0.0.0 '
        'Mobile Safari/537.36',
      );
      expect(samsung.browser, IdentityBrowser.samsung);
      expect(samsung.hints.brand, 'Samsung Internet');
      expect(samsung.hints.brandVersion, '28');
      expect(samsung.hints.chromium, '130');
    });

    test('Chrome on a Chromebook', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      );
      expect(s.system, IdentitySystem.chromeOs);
      expect(s.hints.platform, 'Chrome OS');
      expect(s.platform, 'Linux x86_64');
    });

    test('Chrome on an iPhone is Safari underneath: no Client Hints', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/142.0.7444.77 '
        'Mobile/15E148 Safari/604.1',
      );
      expect(s.browser, IdentityBrowser.safari);
      expect(s.hasClientHints, isFalse);
      expect(s.platform, 'iPhone');
      expect(s.vendor, 'Apple Computer, Inc.');
      expect(s.mobile, isTrue);
    });

    test('an old Firefox on Linux', () {
      final IdentitySpec s = of(
        'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:115.0) '
        'Gecko/20100101 Firefox/115.0',
      );
      expect(s.browser, IdentityBrowser.firefox);
      expect(s.version, '115');
      expect(s.platform, 'Linux x86_64');
      expect(s.oscpu, 'Linux x86_64');
      expect(s.appVersion, '5.0 (X11)');
      expect(s.hasClientHints, isFalse);
    });

    test('something that is no browser changes only the header', () {
      final IdentitySpec s = of(
        'Googlebot/2.1 (+http://www.google.com/bot.html)',
      );
      expect(s.browser, IdentityBrowser.other);
      expect(s.system, IdentitySystem.other);
      expect(s.hasClientHints, isFalse);
      expect(s.hints.platform, 'Unknown');
      expect(s.platform, isNull);
      expect(s.vendor, isNull);
      expect(s.toMap().keys, <String>['id', 'ua', 'hints']);
    });

    test('line breaks never reach the header', () {
      expect(
        cleanUserAgent('  Mozilla/5.0\r\nX-Evil: 1\t(a) '),
        'Mozilla/5.0 X-Evil: 1 (a)',
      );
      expect(
        of('Mozilla/5.0\n(Windows NT 10.0)').userAgent,
        isNot(contains('\n')),
      );
    });

    test('what can\'t be a user agent', () {
      expect(checkUserAgent('   '), UserAgentProblem.empty);
      expect(checkUserAgent('a' * 513), UserAgentProblem.tooLong);
      expect(checkUserAgent('דפדפן/1.0'), UserAgentProblem.notAscii);
      expect(checkUserAgent('MyBrowser/1.0 (test)'), isNull);
    });
  });

  group('versions that keep up with the date', () {
    test('Firefox: about one every four weeks, never ahead', () {
      expect(Identities.firefoxVersion(DateTime.utc(2026, 6, 16)), 152);
      expect(Identities.firefoxVersion(DateTime.utc(2026, 7, 15)), 152);
      expect(Identities.firefoxVersion(DateTime.utc(2026, 7, 16)), 153);
      expect(Identities.firefoxVersion(now), 157);
      // A phone with a wrong clock.
      expect(Identities.firefoxVersion(DateTime.utc(2020)), 152);
    });

    test('Safari: named after the coming year from the autumn', () {
      expect(Identities.safariVersion(DateTime.utc(2026, 5, 1)), '26.4');
      expect(Identities.safariVersion(DateTime.utc(2026, 9, 30)), '26.4');
      expect(Identities.safariVersion(DateTime.utc(2026, 10, 1)), '27.0');
      expect(Identities.safariVersion(now), '27.1');
      expect(Identities.safariVersion(DateTime.utc(2027, 1, 15)), '27.2');
    });
  });

  group('what the engine is told', () {
    const CustomIdentity mine = CustomIdentity(
      id: 'abc',
      name: 'Work laptop',
      userAgent:
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    );

    test('the default is nothing at all', () {
      expect(
        Identities.target('default', const <CustomIdentity>[], now),
        isNull,
      );
      final config = Identities.config(const BrowserSettings(), now);
      expect(config.global, isNull);
      expect(config.rules, isEmpty);
    });

    test('a choice that no longer exists falls back to the default', () {
      expect(
        Identities.known('custom:gone', const <CustomIdentity>[]),
        'default',
      );
      expect(
        Identities.known('netscape-4', const <CustomIdentity>[]),
        'default',
      );
      expect(Identities.known(null, const <CustomIdentity>[]), 'default');
      expect(
        Identities.target('custom:gone', const <CustomIdentity>[], now),
        isNull,
      );
    });

    test('a phone browser comes with its "Desktop site" twin', () {
      final Map<String, Object?> t = Identities.target(
        'safari-iphone',
        const <CustomIdentity>[],
        now,
      )!;
      expect((t['spec']! as Map<String, Object?>)['id'], 'safari-iphone');
      expect((t['desktop']! as Map<String, Object?>)['id'], 'safari-mac');
      final Map<String, Object?> computer = Identities.target(
        'firefox-mac',
        const <CustomIdentity>[],
        now,
      )!;
      expect(computer.containsKey('desktop'), isFalse);
    });

    test('one of the user\'s own', () {
      final Map<String, Object?> t = Identities.target(
        'custom:abc',
        const <CustomIdentity>[mine],
        now,
      )!;
      final Map<String, Object?> spec = t['spec']! as Map<String, Object?>;
      expect(spec['id'], 'custom:abc');
      expect(spec['ua'], mine.userAgent);
      expect((spec['hints']! as Map<String, Object?>)['chromium'], '131');
    });

    test('random: a pool of whole identities', () {
      List<Object?> pool(String choice) =>
          Identities.target(choice, const <CustomIdentity>[], now)!['pool']!
              as List<Object?>;
      final int phones = Identities.presets
          .where((IdentityPreset p) => p.kind == IdentityKind.phone)
          .length;
      final int computers = Identities.presets
          .where((IdentityPreset p) => p.kind == IdentityKind.computer)
          .length;
      // The phone's own Chrome on Android (an empty entry) is one of them.
      expect(pool('random-phone'), hasLength(phones + 1));
      expect(pool('random-phone').first, isEmpty);
      expect(pool('random-computer'), hasLength(computers));
      expect(pool('random'), hasLength(Identities.presets.length + 1));
      for (final Object? entry in pool('random-computer')) {
        final Map<String, Object?> spec =
            (entry! as Map<String, Object?>)['spec']! as Map<String, Object?>;
        expect((spec['hints']! as Map<String, Object?>)['mobile'], isFalse);
      }
    });

    test('settings with site rules', () {
      final BrowserSettings s = const BrowserSettings().copyWith(
        identity: 'firefox-android',
        identityRules: <String, String>{
          'docs.example.com': 'chrome-windows',
          'bank.example': 'default',
          'old.example': 'custom:gone',
          'mine.example': 'custom:abc',
        },
        customIdentities: <CustomIdentity>[mine],
      );
      final config = Identities.config(s, now);
      expect(
        (config.global!['spec']! as Map<String, Object?>)['id'],
        'firefox-android',
      );
      expect(config.rules.keys, s.identityRules.keys);
      // "The default here" is an entry with nothing in it.
      expect(config.rules['bank.example'], isEmpty);
      expect(config.rules['old.example'], isEmpty);
      expect(
        ((config.rules['docs.example.com']! as Map<String, Object?>)['spec']!
            as Map<String, Object?>)['id'],
        'chrome-windows',
      );
    });
  });

  group('settings', () {
    final DateTime at = DateTime(2026, 11, 20);

    test('identity choices survive a round trip', () {
      final BrowserSettings s = const BrowserSettings().copyWith(
        identity: 'random-phone',
        identityRules: <String, String>{'example.com': 'firefox-windows'},
        customIdentities: <CustomIdentity>[
          const CustomIdentity(id: 'abc', name: 'Mine', userAgent: 'Mine/1.0'),
        ],
      );
      final BrowserSettings back = BrowserSettings.fromJson(
        'x',
        s.toJson(),
        at,
      );
      expect(back.identity, 'random-phone');
      expect(back.identityRules, <String, String>{
        'example.com': 'firefox-windows',
      });
      expect(back.customIdentities.single.id, 'abc');
      expect(back.customIdentities.single.name, 'Mine');
      expect(back.customIdentities.single.userAgent, 'Mine/1.0');
    });

    test('settings saved before this existed read as the default', () {
      final Map<String, Object?> old = const BrowserSettings().toJson()
        ..remove('identity')
        ..remove('identityRules')
        ..remove('customIdentities');
      final BrowserSettings s = BrowserSettings.fromJson('x', old, at);
      expect(s.identity, 'default');
      expect(s.identityRules, isEmpty);
      expect(s.customIdentities, isEmpty);
      expect(s.blockTrackers, isTrue);
    });

    test('broken entries from another device are dropped', () {
      final Map<String, Object?> j = const BrowserSettings().toJson()
        ..['identityRules'] = <String, Object?>{
          'a.com': 'chrome-mac',
          'b.com': 5,
        }
        ..['customIdentities'] = <Object?>[
          <String, Object?>{'id': 'ok', 'userAgent': 'Ok/1.0'},
          <String, Object?>{'id': '', 'userAgent': 'NoId/1.0'},
          <String, Object?>{'id': 'empty', 'userAgent': '  '},
          'nonsense',
        ];
      final BrowserSettings s = BrowserSettings.fromJson('x', j, at);
      expect(s.identityRules, <String, String>{'a.com': 'chrome-mac'});
      expect(s.customIdentities.single.id, 'ok');
      // Without a name, the string itself is the name.
      expect(s.customIdentities.single.name, 'Ok/1.0');
    });
  });
}
