import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// Where the language models come from: ZT Browser's own GitHub release,
/// a copy of Mozilla's Firefox Translations models made by the
/// "Translation models" workflow. A plain download: nothing about the page
/// or the person is sent.
const String translationModelsBase =
    'https://github.com/EdoSag/Zero-Trust-Browser/releases/download/translation-models';

/// The language every model translates to or from; other pairs go through
/// it (Hebrew to French is Hebrew to English, then English to French).
const String pivotLanguage = 'en';

/// One file of a model, as the signed list describes it.
class ModelFile {
  const ModelFile({
    required this.asset,
    required this.name,
    required this.gzSize,
    required this.size,
    required this.sha256,
  });

  /// The file's name on the release (gzip).
  final String asset;

  /// Mozilla's name for it, unpacked (tells the engine the precision).
  final String name;
  final int gzSize;
  final int size;
  final String sha256;

  static ModelFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? asset = j['asset'], name = j['name'], gz = j['gzSize'];
    final Object? size = j['size'], sha = j['sha256'];
    if (asset is! String || name is! String || gz is! int) return null;
    if (size is! int || sha is! String || sha.length != 64) return null;
    // Plain file names only: they become paths on the phone.
    final RegExp safe = RegExp(r'^[A-Za-z0-9._-]+$');
    if (!safe.hasMatch(asset) || !safe.hasMatch(name) || name.startsWith('.')) {
      return null;
    }
    return ModelFile(
      asset: asset,
      name: name,
      gzSize: gz,
      size: size,
      sha256: sha.toLowerCase(),
    );
  }
}

/// A model translating [from] one language [to] another.
class TranslationModel {
  const TranslationModel({
    required this.pair,
    required this.from,
    required this.to,
    required this.files,
  });

  /// "en-he".
  final String pair;
  final String from;
  final String to;

  /// model, lex and vocab.
  final Map<String, ModelFile> files;

  int get downloadSize =>
      files.values.fold(0, (int s, ModelFile f) => s + f.gzSize);
  int get diskSize => files.values.fold(0, (int s, ModelFile f) => s + f.size);
}

/// The signed list of models on the release.
class ModelManifest {
  const ModelManifest(this.models);

  final Map<String, TranslationModel> models;

  /// Languages with a model to or from English, English included.
  Set<String> get languages => <String>{
    pivotLanguage,
    for (final TranslationModel m in models.values) ...<String>[m.from, m.to],
  };

  static ModelManifest? parse(String text) {
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (j is! Map || j['version'] != 1 || j['models'] is! Map) return null;
    final Map<String, TranslationModel> models = <String, TranslationModel>{};
    (j['models'] as Map).forEach((Object? pair, Object? m) {
      if (pair is! String || m is! Map || m['files'] is! Map) return;
      final Object? from = m['from'], to = m['to'];
      if (from is! String || to is! String || pair != '$from-$to') return;
      final Map<String, ModelFile> files = <String, ModelFile>{};
      for (final String part in const <String>['model', 'lex', 'vocab']) {
        final ModelFile? f = ModelFile.fromJson((m['files'] as Map)[part]);
        if (f == null) return;
        files[part] = f;
      }
      models[pair] = TranslationModel(
        pair: pair,
        from: from,
        to: to,
        files: files,
      );
    });
    return ModelManifest(models);
  }

  /// The models translating [from] to [to]: the direct one, or two through
  /// English; null when there's no way.
  List<TranslationModel>? route(String from, String to) {
    if (from == to) return null;
    final TranslationModel? direct = models['$from-$to'];
    if (direct != null) return <TranslationModel>[direct];
    if (from == pivotLanguage || to == pivotLanguage) return null;
    final TranslationModel? a = models['$from-$pivotLanguage'];
    final TranslationModel? b = models['$pivotLanguage-$to'];
    return a == null || b == null ? null : <TranslationModel>[a, b];
  }
}

/// The language of a page: what it declares (`<html lang>`), else a guess
/// from the letters of its text for scripts that belong to one language.
/// Null when it can't tell (most Latin-script text).
String? detectLanguage(String declared, String sample) {
  final String code = declared.trim().toLowerCase().replaceAll('_', '-');
  if (code.isNotEmpty) {
    final List<String> parts = code.split('-');
    final String main = parts.first;
    if (main == 'iw') return 'he';
    if (main == 'zh') {
      return parts.contains('tw') ||
              parts.contains('hk') ||
              parts.contains('hant')
          ? 'zh_hant'
          : 'zh';
    }
    if (RegExp(r'^[a-z]{2,3}$').hasMatch(main)) return main;
  }
  final Map<String, int> counts = <String, int>{};
  void add(String k) => counts[k] = (counts[k] ?? 0) + 1;
  int letters = 0;
  for (final int c in sample.runes.take(3000)) {
    if (c >= 0x0590 && c <= 0x05FF) {
      add('he');
    } else if (c >= 0x0600 && c <= 0x06FF) {
      add('ar');
    } else if (c >= 0x0400 && c <= 0x04FF) {
      add('ru');
    } else if (c >= 0x0370 && c <= 0x03FF) {
      add('el');
    } else if (c >= 0x3040 && c <= 0x30FF) {
      add('ja');
    } else if (c >= 0xAC00 && c <= 0xD7AF) {
      add('ko');
    } else if (c >= 0x4E00 && c <= 0x9FFF) {
      add('zh');
    } else if (c >= 0x0E00 && c <= 0x0E7F) {
      add('th');
    } else if (c >= 0x0900 && c <= 0x097F) {
      add('hi');
    } else if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
      add('latin');
    } else {
      continue;
    }
    letters++;
  }
  if (letters < 20) return null;
  // Japanese mixes kana with Chinese characters.
  if ((counts['ja'] ?? 0) > letters * 0.05) return 'ja';
  String? best;
  int most = 0;
  counts.forEach((String k, int n) {
    if (n > most) {
      most = n;
      best = k;
    }
  });
  if (best == null || best == 'latin' || most < letters * 0.5) return null;
  return best;
}

/// Language names as their speakers write them (shown in both app
/// languages, so a Hebrew screen still finds "Deutsch").
const Map<String, String> languageNames = <String, String>{
  'af': 'Afrikaans',
  'ar': 'العربية',
  'az': 'Azərbaycan',
  'be': 'Беларуская',
  'bg': 'Български',
  'bn': 'বাংলা',
  'bs': 'Bosanski',
  'ca': 'Català',
  'cs': 'Čeština',
  'da': 'Dansk',
  'de': 'Deutsch',
  'el': 'Ελληνικά',
  'en': 'English',
  'es': 'Español',
  'et': 'Eesti',
  'eu': 'Euskara',
  'fa': 'فارسی',
  'fi': 'Suomi',
  'fr': 'Français',
  'gl': 'Galego',
  'gu': 'ગુજરાતી',
  'hbs': 'Srpskohrvatski',
  'he': 'עברית',
  'hi': 'हिन्दी',
  'hr': 'Hrvatski',
  'hu': 'Magyar',
  'id': 'Bahasa Indonesia',
  'is': 'Íslenska',
  'it': 'Italiano',
  'ja': '日本語',
  'kn': 'ಕನ್ನಡ',
  'ko': '한국어',
  'lt': 'Lietuvių',
  'lv': 'Latviešu',
  'ml': 'മലയാളം',
  'mr': 'मराठी',
  'ms': 'Bahasa Melayu',
  'nb': 'Norsk bokmål',
  'nl': 'Nederlands',
  'nn': 'Nynorsk',
  'no': 'Norsk',
  'pl': 'Polski',
  'pt': 'Português',
  'ro': 'Română',
  'ru': 'Русский',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'sq': 'Shqip',
  'sr': 'Српски',
  'sv': 'Svenska',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'th': 'ไทย',
  'tl': 'Tagalog',
  'tr': 'Türkçe',
  'ug': 'ئۇيغۇرچە',
  'uk': 'Українська',
  'ur': 'اردو',
  'vi': 'Tiếng Việt',
  'zh': '中文（简体）',
  'zh_hant': '中文（繁體）',
};

String languageName(String code) => languageNames[code] ?? code;

/// The engine's list of installed models (registry.json next to them).
List<Map<String, Object?>> engineRegistry(
  Iterable<TranslationModel> installed,
) {
  const String origin = 'https://translate.zt/models';
  return <Map<String, Object?>>[
    for (final TranslationModel m in installed)
      <String, Object?>{
        'from': m.from,
        'to': m.to,
        'files': <String, Object?>{
          for (final MapEntry<String, ModelFile> f in m.files.entries)
            f.key: <String, String>{
              'name': '$origin/${m.pair}/${f.value.name}',
            },
          'config': <String, String>{
            // Mozilla's "alphas" models carry their own quantisation scales.
            'gemm-precision': m.files['model']!.name.contains('alphas')
                ? 'int8shiftAlphaAll'
                : 'int8shiftAll',
          },
        },
      },
  ];
}

/// Downloads, checks and keeps the language models (B16).
class TranslationModels {
  TranslationModels(this._engine, {http.Client? client, String? publicKey})
    : _client = client ?? http.Client(),
      _publicKey = base64.decode(publicKey ?? blocklistPublicKey);

  final BrowserEngine _engine;
  final http.Client _client;
  final List<int> _publicKey;
  ModelManifest? _manifest;
  DateTime? _manifestAt;

  Future<Directory> dir() async {
    final Directory base = await getApplicationSupportDirectory();
    return Directory('${base.path}/translation-models');
  }

  /// The signed list of models, fetched at most once a day. Throws when
  /// it can't be fetched or its signature doesn't match the app's key.
  Future<ModelManifest> manifest() async {
    final ModelManifest? cached = _manifest;
    final DateTime? at = _manifestAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(days: 1)) {
      return cached;
    }
    final http.Response sig = await _client
        .get(Uri.parse('$translationModelsBase/models.json.sig'))
        .timeout(const Duration(seconds: 30));
    final http.Response list = await _client
        .get(Uri.parse('$translationModelsBase/models.json'))
        .timeout(const Duration(seconds: 30));
    if (sig.statusCode != 200 || list.statusCode != 200) {
      throw const HttpException('models list not available');
    }
    final ModelManifest? m = await verifiedManifest(
      list.bodyBytes,
      sig.body.trim(),
      _publicKey,
    );
    if (m == null) throw const FormatException('models list not trusted');
    _manifest = m;
    _manifestAt = DateTime.now();
    return m;
  }

  /// The list in [bytes] when [signatureBase64] signs it with [publicKey].
  static Future<ModelManifest?> verifiedManifest(
    List<int> bytes,
    String signatureBase64,
    List<int> publicKey,
  ) async {
    final List<int> sig;
    try {
      sig = base64.decode(signatureBase64);
    } on FormatException {
      return null;
    }
    if (sig.length != 64 || publicKey.length != 32) return null;
    final bool ok = await Ed25519().verify(
      bytes,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) return null;
    return ModelManifest.parse(utf8.decode(bytes, allowMalformed: true));
  }

  /// Models on this phone (from the last saved registry).
  Future<List<TranslationModel>> installed() async {
    final File f = File('${(await dir()).path}/installed.json');
    if (!await f.exists()) return const <TranslationModel>[];
    final ModelManifest? m = ModelManifest.parse(await f.readAsString());
    return m?.models.values.toList() ?? const <TranslationModel>[];
  }

  /// Downloads [models] not yet on the phone. [progress] gets bytes done
  /// and total. Each file is checked against the signed list before use.
  Future<void> download(
    List<TranslationModel> models, {
    void Function(int done, int total)? progress,
  }) async {
    final Directory root = await dir();
    final Set<String> have = <String>{
      for (final TranslationModel m in await installed()) m.pair,
    };
    final List<TranslationModel> todo = <TranslationModel>[
      for (final TranslationModel m in models)
        if (!have.contains(m.pair)) m,
    ];
    final int total = todo.fold(
      0,
      (int s, TranslationModel m) => s + m.downloadSize,
    );
    int done = 0;
    progress?.call(0, total);
    for (final TranslationModel m in todo) {
      final Directory d = Directory('${root.path}/${m.pair}');
      await d.create(recursive: true);
      for (final ModelFile f in m.files.values) {
        final http.Request req = http.Request(
          'GET',
          Uri.parse('$translationModelsBase/${f.asset}'),
        );
        final http.StreamedResponse res = await _client
            .send(req)
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) {
          throw HttpException('${f.asset}: ${res.statusCode}');
        }
        final BytesBuilder bytes = BytesBuilder(copy: false);
        await for (final List<int> chunk in res.stream) {
          bytes.add(chunk);
          if (bytes.length > f.gzSize) throw FormatException(f.asset);
          progress?.call(done + bytes.length, total);
        }
        final List<int> gz = bytes.takeBytes();
        done += gz.length;
        final File out = File('${d.path}/${f.name}');
        final bool ok = await Isolate.run(() => _unpack(gz, f, out.path));
        if (!ok) throw FormatException('${f.asset} failed its check');
      }
      have.add(m.pair);
      await _saveInstalled(<TranslationModel>[
        ...(await installed()).where((TranslationModel x) => x.pair != m.pair),
        m,
      ]);
    }
    progress?.call(total, total);
  }

  /// Unpacks [gz] to [path] when its contents match [f]'s size and hash.
  static Future<bool> _unpack(List<int> gz, ModelFile f, String path) async {
    final List<int> raw;
    try {
      raw = gzip.decode(gz);
    } on FormatException {
      return false;
    }
    if (raw.length != f.size) return false;
    final Hash h = await Sha256().hash(raw);
    final String hex = h.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (hex != f.sha256) return false;
    final File tmp = File('$path.tmp');
    await tmp.writeAsBytes(raw, flush: true);
    await tmp.rename(path);
    return true;
  }

  Future<void> delete(String pair) async {
    final Directory root = await dir();
    final List<TranslationModel> keep = (await installed())
        .where((TranslationModel m) => m.pair != pair)
        .toList();
    await _saveInstalled(keep);
    final Directory d = Directory('${root.path}/$pair');
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> deleteAll() async {
    final Directory root = await dir();
    if (await root.exists()) await root.delete(recursive: true);
    await _engine.translatorReset();
  }

  Future<void> _saveInstalled(List<TranslationModel> models) async {
    final Directory root = await dir();
    await root.create(recursive: true);
    final Map<String, Object?> list = <String, Object?>{
      'version': 1,
      'models': <String, Object?>{
        for (final TranslationModel m in models)
          m.pair: <String, Object?>{
            'from': m.from,
            'to': m.to,
            'files': <String, Object?>{
              for (final MapEntry<String, ModelFile> f in m.files.entries)
                f.key: <String, Object?>{
                  'asset': f.value.asset,
                  'name': f.value.name,
                  'gzSize': f.value.gzSize,
                  'size': f.value.size,
                  'sha256': f.value.sha256,
                },
            },
          },
      },
    };
    await File('${root.path}/installed.json').writeAsString(jsonEncode(list));
    await File(
      '${root.path}/registry.json',
    ).writeAsString(jsonEncode(engineRegistry(models)));
    await _engine.translatorReset();
  }

  /// Translates the page in [tabId] on the phone. False when the page's
  /// JavaScript is off.
  Future<bool> translate(String tabId, String from, String to) async =>
      _engine.translatePage(tabId, from, to, (await dir()).path);
}

final translationModelsProvider = Provider<TranslationModels>(
  (ref) => TranslationModels(ref.read(browserEngineProvider)),
);
