import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// The hosts (of [known]) whose cookies and site data should go now: their
/// site isn't open in any tab ([openHosts]) and isn't kept signed in.
/// Grouped by site, so `mail.example.com` stays while `example.com` is open.
List<String> hostsToClear(
  Iterable<String> known,
  Iterable<String> openHosts,
  Iterable<String> keepSignedIn,
) {
  final Set<String> open = <String>{
    for (final String h in openHosts)
      if (h.isNotEmpty) siteOf(h),
  };
  final Set<String> keep = keepSignedIn
      .map((String s) => s.toLowerCase())
      .toSet();
  return <String>[
    for (final String h in known)
      if (!open.contains(siteOf(h)) && !keep.contains(siteOf(h))) h,
  ];
}

/// B24: wipes a site's cookies and site data once its last tab closes,
/// except sites marked "keep me signed in".
///
/// Which hosts may hold data is kept in the core's encrypted preferences
/// on this phone only (never synced), so data left behind by a crash or a
/// killed app is still found and wiped on the next start.
class CookieAutoClear {
  CookieAutoClear(this.ref);

  final Ref ref;
  static const String _key = 'browser_cookie_hosts';

  Set<String>? _known;
  Timer? _saveTimer;

  Future<Set<String>> _load() async {
    final Set<String>? k = _known;
    if (k != null) return k;
    final Set<String> loaded = <String>{};
    try {
      final String? raw = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (raw != null) {
        for (final Object? h in jsonDecode(raw) as List<Object?>) {
          if (h is String) loaded.add(h);
        }
      }
    } on Object {
      // Nothing saved yet, or unreadable: start empty.
    }
    return _known ??= loaded;
  }

  void _queueSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      final Set<String>? k = _known;
      if (k == null) return;
      ref
          .read(ztPreferencesStoreProvider)
          .write(_key, jsonEncode(k.toList()))
          .ignore();
    });
  }

  /// A normal tab showed a page on [url]'s host: it may now hold data.
  Future<void> visited(String? url) async {
    if (!ref.read(browserSettingsProvider).autoClearCookies) return;
    final Uri? u = Uri.tryParse(url ?? '');
    if (u == null || (u.scheme != 'https' && u.scheme != 'http')) return;
    final String host = u.host.toLowerCase();
    if (host.isEmpty) return;
    final Set<String> known = await _load();
    if (known.add(host)) _queueSave();
  }

  /// Wipes the data of every site no tab in [openUrls] shows any more.
  Future<void> sweep(Iterable<String?> openUrls) async {
    final BrowserSettings s = ref.read(browserSettingsProvider);
    if (!s.autoClearCookies) return;
    final Set<String> known = await _load();
    if (known.isEmpty) return;
    final List<String> clear = hostsToClear(known, <String>[
      for (final String? u in openUrls) Uri.tryParse(u ?? '')?.host ?? '',
    ], s.keepSignedIn);
    if (clear.isEmpty) return;
    await ref.read(browserEngineProvider).clearSiteData(clear);
    known.removeAll(clear);
    _queueSave();
  }

  /// Turning the setting off forgets the list (nothing more to wipe).
  Future<void> forget() async {
    _known = <String>{};
    await ref.read(ztPreferencesStoreProvider).write(_key, '[]');
  }
}

final cookieAutoClearProvider = Provider<CookieAutoClear>(CookieAutoClear.new);
