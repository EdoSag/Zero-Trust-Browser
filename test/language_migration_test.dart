import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/app/language.dart';

void main() {
  Future<(String?, SharedPreferences)> migrate(
    Map<String, Object> old, {
    String? core,
    bool onboarded = false,
    String? deviceId,
  }) async {
    SharedPreferences.setMockInitialValues(old);
    final InMemoryPreferencesStore store = InMemoryPreferencesStore();
    if (core != null) await store.write('language', core);
    if (onboarded) await store.write('onboarding_seen', 'true');
    final InMemoryDeviceIdStore ids = InMemoryDeviceIdStore();
    if (deviceId != null) await ids.write(deviceId);
    await migrateBrowserLanguage(store, ids);
    return (await store.read('language'), await SharedPreferences.getInstance());
  }

  test('an explicit Hebrew or English choice moves to the shared setting',
      () async {
    final (String? he, SharedPreferences prefs) =
        await migrate(<String, Object>{'zt_browser.language': 'he'});
    expect(he, 'he');
    expect(prefs.containsKey('zt_browser.language'), isFalse);
    expect((await migrate(<String, Object>{'zt_browser.language': 'en'})).$1, 'en');
  });

  test('an install that followed the phone keeps following it', () async {
    final (String? v, _) = await migrate(
      <String, Object>{'zt_browser.blocklist_checked_at': 1},
    );
    expect(v, 'phone');
  });

  test('an install whose list check never succeeded still keeps the phone',
      () async {
    expect((await migrate(<String, Object>{}, onboarded: true)).$1, 'phone');
    expect((await migrate(<String, Object>{}, deviceId: 'abc')).$1, 'phone');
  });

  test('a new install gets the core default', () async {
    expect((await migrate(<String, Object>{})).$1, isNull);
  });

  test('a choice already made in the shared setting wins', () async {
    final (String? v, _) = await migrate(
      <String, Object>{'zt_browser.language': 'he'},
      core: 'en',
    );
    expect(v, 'en');
  });
}
