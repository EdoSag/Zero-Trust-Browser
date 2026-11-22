import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';
import 'package:zerotrust_browser/engine/engine.dart';

const String _base =
    'https://github.com/EdoSag/Zero-Trust-Browser/releases/download/safety-list';
const String safetyListHeader = '# ZT Browser safety list, format 1.';

/// B-1: keeps the phishing and malware list fresh. Once a day it downloads
/// the newest list from ZT Browser's own GitHub releases (signed with the
/// blocklist's key), checks the signature and hands it to the engine. The
/// list holds hashed site names and the phone looks sites up itself: the
/// pages you open are never sent anywhere.
class SafetyListUpdater {
  SafetyListUpdater(
    this._engine, {
    http.Client? client,
    String publicKey = blocklistPublicKey,
  }) : _client = client ?? http.Client(),
       _publicKey = base64.decode(publicKey);

  final BrowserEngine _engine;
  final http.Client _client;
  final List<int> _publicKey;

  /// New phishing sites appear every hour; a day keeps up without waste.
  static const Duration every = Duration(days: 1);
  static const String _lastCheckKey = 'zt_browser.safety_checked_at';

  /// About 3 MB packed today.
  static const int _maxBytes = 16 * 1024 * 1024;

  Future<DateTime?> lastCheck() async {
    final int? ms = (await SharedPreferences.getInstance()).getInt(
      _lastCheckKey,
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Checks for a newer list when a day has passed (or [force]).
  Future<BlocklistCheck> checkIfDue({bool force = false}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? last = prefs.getInt(_lastCheckKey);
    final DateTime now = DateTime.now();
    if (!force &&
        last != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(last)) < every) {
      return BlocklistCheck.notDue;
    }
    try {
      final BlocklistCheck result = await _update();
      if (result != BlocklistCheck.failed) {
        await prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
      }
      return result;
    } on Object {
      return BlocklistCheck.failed;
    }
  }

  Future<BlocklistCheck> _update() async {
    final http.Response sig = await _client
        .get(Uri.parse('$_base/safety-list.bin.gz.sig'))
        .timeout(const Duration(seconds: 30));
    if (sig.statusCode != 200) return BlocklistCheck.failed;
    final http.Response gz = await _client
        .get(Uri.parse('$_base/safety-list.bin.gz'))
        .timeout(const Duration(minutes: 2));
    if (gz.statusCode != 200 || gz.bodyBytes.length > _maxBytes) {
      return BlocklistCheck.failed;
    }
    final List<int>? raw = await verifiedList(
      gz.bodyBytes,
      sig.body.trim(),
      _publicKey,
    );
    if (raw == null) return BlocklistCheck.failed;
    final String? date = listDate(raw);
    final Map<Object?, Object?> info = await _engine.safetyInfo();
    final String current = info['date'] as String? ?? '';
    final String? path = info['file'] as String?;
    if (date == null || path == null) return BlocklistCheck.failed;
    if (date.compareTo(current) <= 0) return BlocklistCheck.upToDate;
    final File file = File(path);
    await file.parent.create(recursive: true);
    final File tmp = File('$path.tmp');
    await tmp.writeAsBytes(raw, flush: true);
    await tmp.rename(path);
    await _engine.reloadSafetyList();
    return BlocklistCheck.updated;
  }

  /// The list inside [gz] when [signatureBase64] is a valid signature of
  /// it by [publicKey] and it is a ZT Browser safety list; otherwise null.
  static Future<List<int>?> verifiedList(
    List<int> gz,
    String signatureBase64,
    List<int> publicKey,
  ) async {
    final List<int> sigBytes;
    try {
      sigBytes = base64.decode(signatureBase64);
    } on FormatException {
      return null;
    }
    if (sigBytes.length != 64 || publicKey.length != 32) return null;
    final bool ok = await Ed25519().verify(
      gz,
      signature: Signature(
        sigBytes,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) return null;
    final List<int> raw;
    try {
      raw = gzip.decode(gz);
    } on FormatException {
      return null;
    }
    if (raw.length > 4 * _maxBytes) return null;
    final List<int> head = utf8.encode('$safetyListHeader\n');
    if (raw.length < head.length) return null;
    for (int i = 0; i < head.length; i++) {
      if (raw[i] != head[i]) return null;
    }
    return raw;
  }

  /// The `# list-date:` of a list (yyyy-mm-ddThh:mm, UTC).
  static String? listDate(List<int> raw) {
    final String head = latin1.decode(
      raw.sublist(0, raw.length < 300 ? raw.length : 300),
    );
    return RegExp(
      r'^# list-date: ([0-9T:-]{10,16})$',
      multiLine: true,
    ).firstMatch(head)?.group(1);
  }
}

final safetyListUpdaterProvider = Provider<SafetyListUpdater>(
  (ref) => SafetyListUpdater(ref.read(browserEngineProvider)),
);
