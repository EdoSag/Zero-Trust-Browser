import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages ZT Browser's own screens are written in.
const List<Locale> appLocales = <Locale>[Locale('en'), Locale('he')];

/// The language chosen in Settings, or null to follow the phone. Kept on
/// this phone only: a shared tablet can differ from your own phone.
class AppLanguage extends Notifier<Locale?> {
  static const String _key = 'zt_browser.language';

  @override
  Locale? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final String? code = (await SharedPreferences.getInstance()).getString(
        _key,
      );
      if (code != null && appLocales.contains(Locale(code))) {
        state = Locale(code);
      }
    } on Object {
      // Follow the phone.
    }
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
  }
}

final appLanguageProvider = NotifierProvider<AppLanguage, Locale?>(
  AppLanguage.new,
);
