import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/app/app_gate.dart';
import 'package:zerotrust_browser/app/browser_config.dart';
import 'package:zerotrust_browser/app/language.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Shown under Settings > Open-source licences.
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(
        <String>['EasyList, EasyPrivacy and EasyList Cookie List'],
        '''
The tracker, ad and cookie-banner lists come from EasyList, EasyPrivacy and
the EasyList Cookie List (https://easylist.to) by The EasyList authors, used
under the Creative Commons Attribution-ShareAlike 3.0 licence
(https://creativecommons.org/licenses/by-sa/3.0/). ZT Browser keeps only the
rules that block whole host names and the element-hiding rules written as
plain CSS.''',
      ),
    ),
  );
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(<String>[
      'Readability.js',
    ], await rootBundle.loadString('assets/reader/LICENSE'));
  });
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(
        <String>['ZXing Android Embedded'],
        '''
QR code scanning uses ZXing ("Zebra Crossing") and ZXing Android Embedded
(https://github.com/journeyapps/zxing-android-embedded), licensed under the
Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).''',
      ),
    ),
  );
  await migrateBrowserLanguage();
  await ZtLanguageController.preload();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(
    ProviderScope(
      overrides: [ztAppConfigProvider.overrideWithValue(browserAppConfig)],
      child: const ZeroTrustBrowserApp(),
    ),
  );
}

class ZeroTrustBrowserApp extends ConsumerWidget {
  const ZeroTrustBrowserApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ZtThemeBuilder(
      builder: (context, theme, darkTheme, mode) => MaterialApp(
        // On-device task switcher label; the store name is Zero-Trust Browser.
        title: 'ZT Browser',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: mode,
        // English (default) or Hebrew, from Settings → Appearance →
        // Language, shared with every Zero-Trust app's core screens.
        locale: ref.watch(ztLanguageProvider),
        localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
        supportedLocales: ZtLanguages.supported,
        home: const AppGate(),
        // Any touch on any screen counts as activity for auto-lock.
        builder: (BuildContext context, Widget? child) => Listener(
          onPointerDown: (_) =>
              ref.read(vaultControllerProvider.notifier).touch(),
          child: child,
        ),
      ),
    );
  }
}
