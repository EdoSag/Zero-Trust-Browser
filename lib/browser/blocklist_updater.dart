import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// The key the weekly "Blocklist" workflow signs lists with (Ed25519). Only
/// a list signed with its private half, kept as a GitHub Actions secret, is
/// ever used: a changed file on the download server is refused.
const String blocklistPublicKey =
    'HlsU7OZwBpMNRNqCFn++sn+GL6o+rEG1f8KOpO4V2mo=';

const String _base =
    'https://github.com/EdoSag/Zero-Trust-Browser/releases/download/blocklist';
const String _header = '# ZT Browser blocklist, format 1.';

/// The result of an update check, for the settings screen.
enum BlocklistCheck { updated, upToDate, notDue, failed }

/// Keeps the tracker, ad and cookie-banner list fresh without app updates:
/// once a week it downloads the newest list from ZT Browser's own GitHub
/// releases, checks its signature, and hands it to the engine. Nothing
/// about you is sent: it is a plain download, like any web page.
class BlocklistUpdater {
  BlocklistUpdater(
    this._engine, {
    http.Client? client,
    String publicKey = blocklistPublicKey,
  }) : _client = client ?? http.Client(),
       _publicKey = base64.decode(publicKey);

  final BrowserEngine _engine;
  final http.Client _client;
  final List<int> _publicKey;

  static const Duration every = Duration(days: 7);
  static const String _lastCheckKey = 'zt_browser.blocklist_checked_at';

  /// The newest list is at most this big (about 2.5 MB unpacked today).
  static const int _maxBytes = 8 * 1024 * 1024;

  Future<DateTime?> lastCheck() async {
    final int? ms = (await SharedPreferences.getInstance()).getInt(
      _lastCheckKey,
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Checks for a newer list when a week has passed (or [force]).
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
      await prefs.setInt(_lastCheckKey, now.millisecondsSinceEpoch);
      return result;
    } on Object {
      return BlocklistCheck.failed;
    }
  }

  Future<BlocklistCheck> _update() async {
    final http.Response sig = await _client
        .get(Uri.parse('$_base/blocklist.txt.gz.sig'))
        .timeout(const Duration(seconds: 30));
    if (sig.statusCode != 200) return BlocklistCheck.failed;
    final http.Response gz = await _client
        .get(Uri.parse('$_base/blocklist.txt.gz'))
        .timeout(const Duration(minutes: 2));
    if (gz.statusCode != 200 || gz.bodyBytes.length > _maxBytes) {
      return BlocklistCheck.failed;
    }
    final String? text = await verifiedList(
      gz.bodyBytes,
      sig.body.trim(),
      _publicKey,
    );
    if (text == null) return BlocklistCheck.failed;
    final String? date = listDate(text);
    final Map<Object?, Object?> info = await _engine.blocklistInfo();
    final String current = info['date'] as String? ?? '';
    final String? path = info['file'] as String?;
    if (date == null || path == null) return BlocklistCheck.failed;
    if (date.compareTo(current) <= 0) return BlocklistCheck.upToDate;
    final File file = File(path);
    await file.parent.create(recursive: true);
    final File tmp = File('$path.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(path);
    await _engine.reloadBlocklist();
    return BlocklistCheck.updated;
  }

  /// The list inside [gz] when [signatureBase64] is a valid signature of
  /// it by [publicKey] and it is a ZT Browser list; otherwise null.
  static Future<String?> verifiedList(
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
    final String text = utf8.decode(raw, allowMalformed: true);
    if (!text.startsWith(_header) || !text.contains('\n!hosts\n')) return null;
    return text;
  }

  /// The `# list-date:` of a list (yyyy-mm-ddThh:mm, UTC).
  static String? listDate(String text) =>
      RegExp(r'^# list-date: ([0-9T:-]{10,16})$', multiLine: true)
          .firstMatch(
            text.substring(0, text.length < 2000 ? text.length : 2000),
          )
          ?.group(1);
}

final blocklistUpdaterProvider = Provider<BlocklistUpdater>(
  (ref) => BlocklistUpdater(ref.read(browserEngineProvider)),
);
