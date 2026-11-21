import 'package:zerotrust_browser/data/models.dart';

/// B42: which browser a page is told it is (the "user agent").
///
/// An identity starts from one user agent string. Everything else a site
/// can read about the browser is worked out from that string, so the
/// parts always agree: the Client Hints headers and
/// `navigator.userAgentData` (Chrome, Edge and the like have them;
/// Firefox and Safari don't), and `navigator.platform`, `vendor`,
/// `oscpu` and the rest.
///
/// The engine applies them (Identity.kt): a tab's own choice first, then
/// the rule for the site, then the choice in Settings, then the default,
/// which is Chrome on Android at the phone's real version and costs
/// nothing per page.
///
/// `{chrome}` and `{android}` in a string stand for the phone's engine
/// and Android versions; the engine fills them in.

/// The browser an identity claims to be.
enum IdentityBrowser { chrome, edge, opera, samsung, firefox, safari, other }

/// The system an identity claims to run on.
enum IdentitySystem {
  android,
  windows,
  mac,
  linux,
  chromeOs,
  iphone,
  ipad,
  other,
}

/// Where a preset is listed.
enum IdentityKind { phone, tablet, computer }

/// The Client Hints of an identity: the `Sec-CH-UA` headers and
/// `navigator.userAgentData`.
///
/// [brand] null is a browser without Client Hints. The engine can't leave
/// out the three basic headers, so for those they name the claimed system
/// and no browser, and `navigator.userAgentData` is removed.
class ClientHints {
  const ClientHints({
    required this.brand,
    required this.brandVersion,
    required this.chromium,
    required this.platform,
    required this.platformVersion,
    required this.arch,
    required this.bitness,
    required this.model,
    required this.mobile,
    required this.formFactor,
  });

  /// "Google Chrome", "Microsoft Edge"...
  final String? brand;

  /// Major versions of the browser and of the Chromium inside it.
  final String brandVersion;
  final String chromium;

  /// `Sec-CH-UA-Platform` and `-Platform-Version`.
  final String platform;
  final String platformVersion;

  /// `Sec-CH-UA-Arch` ("x86", "arm", or empty on Android) and `-Bitness`
  /// (64, or 0 for empty).
  final String arch;
  final int bitness;
  final String model;
  final bool mobile;

  /// `Sec-CH-UA-Form-Factors`: Mobile, Tablet or Desktop.
  final String formFactor;

  Map<String, Object?> toMap() => <String, Object?>{
    'brand': brand,
    'brandVersion': brandVersion,
    'chromium': chromium,
    'platform': platform,
    'platformVersion': platformVersion,
    'arch': arch,
    'bitness': bitness,
    'model': model,
    'mobile': mobile,
    'formFactor': formFactor,
  };
}

/// One identity, complete: the user agent and all that follows from it.
/// Null fields are ones the engine already gets right by itself.
class IdentitySpec {
  const IdentitySpec({
    required this.id,
    required this.userAgent,
    required this.browser,
    required this.system,
    required this.version,
    required this.hints,
    this.platform,
    this.vendor,
    this.oscpu,
    this.appVersion,
    this.productSub,
    this.touch,
  });

  final String id;
  final String userAgent;
  final IdentityBrowser browser;
  final IdentitySystem system;

  /// The browser's major version, for showing ("142", or `{chrome}`).
  final String version;
  final ClientHints hints;

  /// `navigator.platform`, `vendor`, `oscpu`, `appVersion`, `productSub`
  /// and `maxTouchPoints`.
  final String? platform;
  final String? vendor;
  final String? oscpu;
  final String? appVersion;
  final String? productSub;
  final int? touch;

  /// Chrome, Edge and other browsers built on Chromium have Client Hints.
  bool get hasClientHints => hints.brand != null;

  /// True on a phone (`Sec-CH-UA-Mobile: ?1`).
  bool get mobile => hints.mobile;

  /// For the engine (`setIdentity`, `setTabIdentity`).
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'ua': userAgent,
    'hints': hints.toMap(),
    'platform': ?platform,
    'vendor': ?vendor,
    'oscpu': ?oscpu,
    'appVersion': ?appVersion,
    'productSub': ?productSub,
    'touch': ?touch,
  };

  /// Works out an identity from its user agent string.
  ///
  /// [touch] sets `navigator.maxTouchPoints` where the string can't tell
  /// (an iPad says it is a Mac).
  factory IdentitySpec.fromUserAgent(
    String id,
    String userAgent, {
    int? touch,
  }) {
    final String ua = cleanUserAgent(userAgent);
    final IdentitySystem system = _systemOf(ua);
    final IdentityBrowser browser = _browserOf(ua);
    final bool mobile =
        system == IdentitySystem.iphone ||
        (system != IdentitySystem.ipad &&
            RegExp(r'\bMobi(le)?\b').hasMatch(ua));

    // navigator.platform, as each system's browsers say it.
    final String? platform = switch (system) {
      IdentitySystem.windows => 'Win32',
      IdentitySystem.mac => 'MacIntel',
      IdentitySystem.linux || IdentitySystem.chromeOs => 'Linux x86_64',
      IdentitySystem.iphone => 'iPhone',
      IdentitySystem.ipad => 'iPad',
      // The engine's own value is Chrome on Android's.
      IdentitySystem.android =>
        browser == IdentityBrowser.firefox ? 'Linux aarch64' : null,
      IdentitySystem.other => null,
    };

    switch (browser) {
      case IdentityBrowser.chrome ||
          IdentityBrowser.edge ||
          IdentityBrowser.opera ||
          IdentityBrowser.samsung:
        final String chromium =
            _version(ua, r'(?:Chrome|Chromium)/') ?? '{chrome}';
        final String own =
            switch (browser) {
              IdentityBrowser.edge => _version(ua, r'Edg(?:A|e)?/'),
              IdentityBrowser.opera => _version(ua, r'OPR/'),
              IdentityBrowser.samsung => _version(ua, r'SamsungBrowser/'),
              _ => null,
            } ??
            chromium;
        final bool android = system == IdentitySystem.android;
        return IdentitySpec(
          id: id,
          userAgent: ua,
          browser: browser,
          system: system,
          version: own,
          platform: platform,
          // A Mac with touch points is taken for an iPad.
          touch: touch ?? (system == IdentitySystem.mac ? 0 : null),
          hints: ClientHints(
            brand: switch (browser) {
              IdentityBrowser.edge => 'Microsoft Edge',
              IdentityBrowser.opera => 'Opera',
              IdentityBrowser.samsung => 'Samsung Internet',
              _ => 'Google Chrome',
            },
            brandVersion: own,
            chromium: chromium,
            platform: _hintPlatform(system),
            platformVersion: _hintPlatformVersion(system, ua),
            arch: switch (system) {
              IdentitySystem.android || IdentitySystem.other => '',
              IdentitySystem.mac => 'arm',
              _ => 'x86',
            },
            bitness: android || system == IdentitySystem.other ? 0 : 64,
            model: android ? _androidModel(ua) : '',
            mobile: mobile,
            formFactor: mobile
                ? 'Mobile'
                : android
                ? 'Tablet'
                : 'Desktop',
          ),
        );
      case IdentityBrowser.firefox:
        final String version = _version(ua, r'Firefox/') ?? '';
        final String androidVersion =
            RegExp(r'Android (\{android\}|[\d.]+)').firstMatch(ua)?.group(1) ??
            '';
        return IdentitySpec(
          id: id,
          userAgent: ua,
          browser: browser,
          system: system,
          version: version,
          platform: platform,
          vendor: '',
          productSub: '20100101',
          oscpu: switch (system) {
            IdentitySystem.windows => 'Windows NT 10.0; Win64; x64',
            IdentitySystem.mac => 'Intel Mac OS X 10.15',
            IdentitySystem.android => 'Linux aarch64',
            IdentitySystem.linux || IdentitySystem.chromeOs => 'Linux x86_64',
            _ => null,
          },
          appVersion: switch (system) {
            IdentitySystem.windows => '5.0 (Windows)',
            IdentitySystem.mac => '5.0 (Macintosh)',
            IdentitySystem.android =>
              androidVersion.isEmpty
                  ? '5.0 (Android)'
                  : '5.0 (Android $androidVersion)',
            IdentitySystem.linux || IdentitySystem.chromeOs => '5.0 (X11)',
            _ => null,
          },
          touch: touch ?? (system == IdentitySystem.mac ? 0 : null),
          hints: _noHints(system, mobile),
        );
      case IdentityBrowser.safari:
        return IdentitySpec(
          id: id,
          userAgent: ua,
          browser: browser,
          system: system,
          version: _version(ua, r'Version/') ?? '',
          platform: platform,
          vendor: 'Apple Computer, Inc.',
          touch:
              touch ??
              switch (system) {
                IdentitySystem.iphone || IdentitySystem.ipad => 5,
                IdentitySystem.mac => 0,
                _ => null,
              },
          hints: _noHints(system, mobile),
        );
      case IdentityBrowser.other:
        return IdentitySpec(
          id: id,
          userAgent: ua,
          browser: browser,
          system: system,
          version: '',
          platform: platform,
          touch: touch,
          hints: _noHints(system, mobile),
        );
    }
  }

  static ClientHints _noHints(IdentitySystem system, bool mobile) =>
      ClientHints(
        brand: null,
        brandVersion: '',
        chromium: '',
        platform: _hintPlatform(system),
        platformVersion: '',
        arch: '',
        bitness: 0,
        model: '',
        mobile: mobile,
        formFactor: mobile
            ? 'Mobile'
            : system == IdentitySystem.ipad || system == IdentitySystem.android
            ? 'Tablet'
            : 'Desktop',
      );

  static IdentitySystem _systemOf(String ua) {
    if (ua.contains('Windows')) return IdentitySystem.windows;
    if (ua.contains('Android')) return IdentitySystem.android;
    if (ua.contains('iPhone') || ua.contains('iPod')) {
      return IdentitySystem.iphone;
    }
    if (ua.contains('iPad')) return IdentitySystem.ipad;
    if (ua.contains('Macintosh') || ua.contains('Mac OS X')) {
      return IdentitySystem.mac;
    }
    if (ua.contains('CrOS')) return IdentitySystem.chromeOs;
    if (ua.contains('Linux') || ua.contains('X11')) return IdentitySystem.linux;
    return IdentitySystem.other;
  }

  static IdentityBrowser _browserOf(String ua) {
    // Every browser on an iPhone is Safari underneath.
    if (RegExp(r'(CriOS|FxiOS|EdgiOS|OPiOS)/').hasMatch(ua)) {
      return IdentityBrowser.safari;
    }
    if (RegExp(r'Firefox/\d').hasMatch(ua)) return IdentityBrowser.firefox;
    final bool chromium = RegExp(
      r'(Chrome|Chromium)/(\d|\{chrome\})',
    ).hasMatch(ua);
    if (chromium && RegExp(r'Edg(A|e)?/').hasMatch(ua)) {
      return IdentityBrowser.edge;
    }
    if (chromium && ua.contains('OPR/')) return IdentityBrowser.opera;
    if (chromium && ua.contains('SamsungBrowser/')) {
      return IdentityBrowser.samsung;
    }
    if (chromium) return IdentityBrowser.chrome;
    if (ua.contains('AppleWebKit/') &&
        ua.contains('Safari/') &&
        ua.contains('Version/')) {
      return IdentityBrowser.safari;
    }
    return IdentityBrowser.other;
  }

  /// The major version after [token] (a regular expression), or the
  /// `{chrome}` placeholder standing there.
  static String? _version(String ua, String token) =>
      RegExp('$token(\\{chrome\\}|\\d+)').firstMatch(ua)?.group(1);

  static String _hintPlatform(IdentitySystem system) => switch (system) {
    IdentitySystem.android => 'Android',
    IdentitySystem.windows => 'Windows',
    IdentitySystem.mac => 'macOS',
    IdentitySystem.linux => 'Linux',
    IdentitySystem.chromeOs => 'Chrome OS',
    IdentitySystem.iphone || IdentitySystem.ipad => 'iOS',
    IdentitySystem.other => 'Unknown',
  };

  static String _hintPlatformVersion(IdentitySystem system, String ua) {
    switch (system) {
      case IdentitySystem.windows:
        // Windows 11 (the user agent says "NT 10.0" for 10 and 11 alike).
        return '19.0.0';
      case IdentitySystem.mac:
        return '15.6.0';
      case IdentitySystem.linux:
        return '6.8.0';
      case IdentitySystem.chromeOs:
        return '16328.55.0';
      case IdentitySystem.android:
        final String? v = RegExp(
          r'Android (\{android\}|[\d.]+)',
        ).firstMatch(ua)?.group(1);
        // Chrome's user agent always says "Android 10; K": the real
        // version is only in the hint.
        if (v == null || v == '{android}' || _isShortened(ua)) {
          return '{android}.0.0';
        }
        final List<String> parts = v.split('.');
        while (parts.length < 3) {
          parts.add('0');
        }
        return parts.take(3).join('.');
      case IdentitySystem.iphone || IdentitySystem.ipad || IdentitySystem.other:
        return '';
    }
  }

  static bool _isShortened(String ua) => ua.contains('Android 10; K)');

  /// The phone model a full Android user agent names; none in Chrome's
  /// shortened form.
  static String _androidModel(String ua) {
    if (_isShortened(ua)) return '';
    final String? inside = RegExp(
      r'\(([^)]*Android[^)]*)\)',
    ).firstMatch(ua)?.group(1);
    if (inside == null) return '';
    final List<String> parts = inside
        .split(';')
        .map((String p) => p.trim())
        .toList();
    final int at = parts.indexWhere((String p) => p.startsWith('Android'));
    if (at < 0 || at + 1 >= parts.length) return '';
    final String model = parts[at + 1]
        .replaceFirst(RegExp(r'\s+Build/.*$'), '')
        .trim();
    return model == 'wv' || model.startsWith('rv:') || model == 'Mobile'
        ? ''
        : model;
  }
}

/// [input] as one header line: no line breaks or control characters, no
/// spaces at the ends.
String cleanUserAgent(String input) =>
    input.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ').trim();

/// Why a user agent the user typed can't be used; null when it can.
enum UserAgentProblem { empty, tooLong, notAscii }

UserAgentProblem? checkUserAgent(String input) {
  final String ua = cleanUserAgent(input);
  if (ua.isEmpty) return UserAgentProblem.empty;
  if (ua.length > 512) return UserAgentProblem.tooLong;
  // Header values are plain ASCII.
  if (ua.codeUnits.any((int c) => c > 0x7E)) return UserAgentProblem.notAscii;
  return null;
}

/// A browser the user can pick from the list.
class IdentityPreset {
  const IdentityPreset(
    this.id,
    this.kind,
    this.template, {
    this.desktopId,
    this.touch,
  });

  final String id;
  final IdentityKind kind;

  /// The user agent; `{firefox}` and `{safari}` are today's versions.
  final String template;

  /// The preset to use for "Desktop site" (phones only).
  final String? desktopId;
  final int? touch;

  String userAgent(DateTime now) => template
      .replaceAll('{firefox}', '${Identities.firefoxVersion(now)}')
      .replaceAll('{safari}', Identities.safariVersion(now));

  IdentitySpec spec(DateTime now) =>
      IdentitySpec.fromUserAgent(id, userAgent(now), touch: touch);
}

/// What a tab shows as its identity, for the settings screen.
class DeviceIdentity {
  const DeviceIdentity({
    this.chrome = '',
    this.chromeFull = '',
    this.android = '',
    this.defaultUserAgent = '',
    this.desktopUserAgent = '',
    this.clientHints = true,
  });

  /// The phone's engine version: major ("142") and full.
  final String chrome;
  final String chromeFull;
  final String android;

  /// What the default sends, and with "Desktop site" on.
  final String defaultUserAgent;
  final String desktopUserAgent;

  /// False on an old engine that can't set Client Hints.
  final bool clientHints;

  /// [text] with the phone's versions filled in, as the engine does.
  String fill(String text) => chrome.isEmpty
      ? text
      : text.replaceAll('{chrome}', chrome).replaceAll('{android}', android);

  static DeviceIdentity fromMap(Map<Object?, Object?> m) => DeviceIdentity(
    chrome: m['chrome'] as String? ?? '',
    chromeFull: m['chromeFull'] as String? ?? '',
    android: m['android'] as String? ?? '',
    defaultUserAgent: m['defaultUa'] as String? ?? '',
    desktopUserAgent: m['desktopUa'] as String? ?? '',
    clientHints: m['clientHints'] as bool? ?? true,
  );
}

/// The identities to choose from, and how a choice becomes what the
/// engine is told.
///
/// A choice is a short text kept in the settings: [defaultId], a preset's
/// id, one of the three random ones, or `custom:` and the id of one of
/// the user's own.
abstract final class Identities {
  static const String defaultId = 'default';

  /// What the engine reports for the default with "Desktop site" on.
  static const String defaultDesktopId = 'default-desktop';

  /// A different browser for each site: among phones, computers, or all.
  static const String randomPhone = 'random-phone';
  static const String randomComputer = 'random-computer';
  static const String randomAny = 'random';
  static const List<String> randoms = <String>[
    randomPhone,
    randomComputer,
    randomAny,
  ];

  static const String _customPrefix = 'custom:';

  static const String _chromeTail =
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{chrome}.0.0.0';

  static const List<IdentityPreset> presets = <IdentityPreset>[
    // ---- Phones ----
    IdentityPreset(
      'firefox-android',
      IdentityKind.phone,
      'Mozilla/5.0 (Android {android}; Mobile; rv:{firefox}.0) '
          'Gecko/{firefox}.0 Firefox/{firefox}.0',
      desktopId: 'firefox-linux',
    ),
    IdentityPreset(
      'edge-android',
      IdentityKind.phone,
      'Mozilla/5.0 (Linux; Android 10; K) $_chromeTail Mobile Safari/537.36 '
          'EdgA/{chrome}.0.0.0',
      desktopId: 'edge-windows',
    ),
    IdentityPreset(
      'safari-iphone',
      IdentityKind.phone,
      // Safari stopped raising the iOS number in its user agent at 18.6.
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/{safari} '
          'Mobile/15E148 Safari/604.1',
      desktopId: 'safari-mac',
    ),
    // ---- Tablets ----
    IdentityPreset(
      'safari-ipad',
      IdentityKind.tablet,
      // An iPad says it is a Mac; only its touch screen gives it away.
      _safariMac,
      touch: 5,
    ),
    // ---- Computers ----
    IdentityPreset(
      'chrome-windows',
      IdentityKind.computer,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) $_chromeTail Safari/537.36',
    ),
    IdentityPreset(
      'chrome-mac',
      IdentityKind.computer,
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) $_chromeTail '
          'Safari/537.36',
    ),
    IdentityPreset(
      'chrome-linux',
      IdentityKind.computer,
      'Mozilla/5.0 (X11; Linux x86_64) $_chromeTail Safari/537.36',
    ),
    IdentityPreset(
      'edge-windows',
      IdentityKind.computer,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) $_chromeTail Safari/537.36 '
          'Edg/{chrome}.0.0.0',
    ),
    IdentityPreset(
      'firefox-windows',
      IdentityKind.computer,
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:{firefox}.0) '
          'Gecko/20100101 Firefox/{firefox}.0',
    ),
    IdentityPreset(
      'firefox-mac',
      IdentityKind.computer,
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:{firefox}.0) '
          'Gecko/20100101 Firefox/{firefox}.0',
    ),
    IdentityPreset(
      'firefox-linux',
      IdentityKind.computer,
      'Mozilla/5.0 (X11; Linux x86_64; rv:{firefox}.0) '
          'Gecko/20100101 Firefox/{firefox}.0',
    ),
    IdentityPreset('safari-mac', IdentityKind.computer, _safariMac),
  ];

  static const String _safariMac =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/{safari} '
      'Safari/605.1.15';

  static IdentityPreset? preset(String id) {
    for (final IdentityPreset p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  static String customChoice(String id) => '$_customPrefix$id';

  static CustomIdentity? custom(String choice, List<CustomIdentity> all) {
    if (!choice.startsWith(_customPrefix)) return null;
    final String id = choice.substring(_customPrefix.length);
    for (final CustomIdentity c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// [choice] when it still names something, else the default (a custom
  /// identity removed on another device, a preset from a newer version).
  static String known(String? choice, List<CustomIdentity> custom) {
    if (choice == null) return defaultId;
    if (randoms.contains(choice) || preset(choice) != null) return choice;
    if (Identities.custom(choice, custom) != null) return choice;
    return defaultId;
  }

  /// The identity [choice] stands for, or null for the default and the
  /// random ones.
  static IdentitySpec? spec(
    String choice,
    List<CustomIdentity> custom,
    DateTime now,
  ) {
    final IdentityPreset? p = preset(choice);
    if (p != null) return p.spec(now);
    final CustomIdentity? c = Identities.custom(choice, custom);
    if (c != null) return IdentitySpec.fromUserAgent(choice, c.userAgent);
    return null;
  }

  /// What the engine is told for [choice]: null for the default, else
  /// one identity (with the one for "Desktop site") or a pool to pick
  /// from at random.
  static Map<String, Object?>? target(
    String choice,
    List<CustomIdentity> custom,
    DateTime now,
  ) {
    switch (known(choice, custom)) {
      case defaultId:
        return null;
      case randomPhone:
        return _pool(
          now,
          (IdentityPreset p) => p.kind == IdentityKind.phone,
          true,
        );
      case randomComputer:
        return _pool(
          now,
          (IdentityPreset p) => p.kind == IdentityKind.computer,
          false,
        );
      case randomAny:
        return _pool(now, (IdentityPreset p) => true, true);
    }
    final IdentitySpec? s = spec(choice, custom, now);
    if (s == null) return null;
    final String? desktopId = preset(choice)?.desktopId;
    return <String, Object?>{
      'spec': s.toMap(),
      'desktop': ?(desktopId == null
          ? null
          : preset(desktopId)?.spec(now).toMap()),
    };
  }

  /// A pool of presets; [withDefault] adds the phone's own Chrome on
  /// Android (an entry with nothing in it).
  static Map<String, Object?> _pool(
    DateTime now,
    bool Function(IdentityPreset) include,
    bool withDefault,
  ) => <String, Object?>{
    'pool': <Map<String, Object?>>[
      if (withDefault) <String, Object?>{},
      for (final IdentityPreset p in presets)
        if (include(p)) target(p.id, const <CustomIdentity>[], now)!,
    ],
  };

  /// The settings as the engine wants them (`setIdentity`): the identity
  /// for all sites and the one for each site with its own.
  static ({Map<String, Object?>? global, Map<String, Object?> rules}) config(
    BrowserSettings s,
    DateTime now,
  ) => (
    global: target(s.identity, s.customIdentities, now),
    rules: <String, Object?>{
      for (final MapEntry<String, String> e in s.identityRules.entries)
        // An empty entry is "the default here", whatever the rest gets.
        e.key:
            target(e.value, s.customIdentities, now) ??
            const <String, Object?>{},
    },
  );

  /// Firefox's version on [now]. A new one comes out about every four
  /// weeks (152 on 16 June 2026); counting 30 days each never names a
  /// version that isn't out yet.
  static int firefoxVersion(DateTime now) {
    final int days = now.toUtc().difference(DateTime.utc(2026, 6, 16)).inDays;
    return days <= 0 ? 152 : 152 + days ~/ 30;
  }

  /// Safari's version on [now]. Since 2025 it is named after the coming
  /// year and comes out in September (26.0 in September 2025), with a
  /// point release every month or two.
  static String safariVersion(DateTime now) {
    final DateTime t = now.toUtc();
    final int major = t.year - 2000 + (t.month >= 10 ? 1 : 0);
    final int minor = switch (t.month) {
      10 => 0,
      11 || 12 => 1,
      1 || 2 => 2,
      3 || 4 => 3,
      _ => 4,
    };
    return '$major.$minor';
  }
}
