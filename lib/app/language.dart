import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// ZT Browser used to keep its own language choice (and followed the phone
/// by default). The language now lives in the shared core setting under
/// Settings → Appearance → Language, like every Zero-Trust app.
///
/// Moves the old choice across once, before [ZtLanguageController.preload]:
/// - an explicit English or Hebrew choice is kept;
/// - an install that already ran but never chose keeps following the phone,
///   so nobody's browser switches language after the update;
/// - a new install gets the core default, English.
Future<void> migrateBrowserLanguage([
  PreferencesStore? store,
  DeviceIdStore? deviceIds,
]) async {
  const String oldKey = 'zt_browser.language';
  const String ranKey = 'zt_browser.blocklist_checked_at';
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? old = prefs.getString(oldKey);
    final PreferencesStore core = store ?? SecurePreferencesStore();
    // Signs that this install ran before, none of which needs a network
    // request to have succeeded: the weekly list check, the welcome
    // screens, or the id sync gives a device once signed in.
    final bool ranBefore =
        old != null ||
        prefs.containsKey(ranKey) ||
        await core.read('onboarding_seen') != null ||
        await (deviceIds ?? SecureDeviceIdStore()).read() != null;
    if (!ranBefore) return;
    if (await core.read('language') == null) {
      await core.write('language', old == 'en' || old == 'he' ? old! : 'phone');
    }
    await prefs.remove(oldKey);
  } on Object {
    // Unreadable: the core default applies.
  }
}
