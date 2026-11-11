import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/translation.dart';

Map<String, Object?> _model(String from, String to) => <String, Object?>{
  'from': from,
  'to': to,
  'architecture': 'tiny',
  'files': <String, Object?>{
    for (final String part in <String>['model', 'lex', 'vocab'])
      part: <String, Object?>{
        'asset': '$from-$to.$part.bin.gz',
        'name': part == 'model'
            ? 'model.$from$to.intgemm.alphas.bin'
            : '$part.$from$to.bin',
        'gzSize': 10 * 1024 * 1024,
        'size': 15 * 1024 * 1024,
        'sha256': 'a' * 64,
      },
  },
};

String _manifest(List<Map<String, Object?>> models) => jsonEncode(
  <String, Object?>{
    'version': 1,
    'models': <String, Object?>{
      for (final Map<String, Object?> m in models) '${m['from']}-${m['to']}': m,
    },
  },
);

void main() {
  final ModelManifest m = ModelManifest.parse(
    _manifest(<Map<String, Object?>>[
      _model('en', 'he'),
      _model('he', 'en'),
      _model('fr', 'en'),
      _model('en', 'fr'),
    ]),
  )!;

  test('the list reads models and their languages', () {
    expect(m.models.keys, containsAll(<String>['en-he', 'he-en', 'fr-en']));
    expect(m.languages, <String>{'en', 'he', 'fr'});
    expect(m.models['en-he']!.downloadSize, 30 * 1024 * 1024);
  });

  test('routes go direct, or through English', () {
    expect(m.route('en', 'he')!.map((TranslationModel x) => x.pair), <String>[
      'en-he',
    ]);
    expect(m.route('he', 'fr')!.map((TranslationModel x) => x.pair), <String>[
      'he-en',
      'en-fr',
    ]);
    expect(m.route('he', 'he'), isNull);
    expect(m.route('de', 'en'), isNull);
  });

  test('file names that could leave the models folder are refused', () {
    final Map<String, Object?> bad = _model('en', 'he');
    ((bad['files']! as Map<String, Object?>)['vocab']!
            as Map<String, Object?>)['name'] =
        '../../shared_prefs/x.xml';
    final ModelManifest? parsed = ModelManifest.parse(
      _manifest(<Map<String, Object?>>[bad]),
    );
    expect(parsed!.models, isEmpty);
    expect(ModelManifest.parse('not json'), isNull);
    expect(ModelManifest.parse('{"version":2,"models":{}}'), isNull);
  });

  test('only a list signed with the app key is trusted', () async {
    final Ed25519 ed = Ed25519();
    final SimpleKeyPair key = await ed.newKeyPair();
    final List<int> pub = (await key.extractPublicKey()).bytes;
    final List<int> bytes = utf8.encode(
      _manifest(<Map<String, Object?>>[_model('en', 'he')]),
    );
    final String sig = base64.encode(
      (await ed.sign(bytes, keyPair: key)).bytes,
    );
    expect(
      await TranslationModels.verifiedManifest(bytes, sig, pub),
      isNotNull,
    );
    final List<int> changed = List<int>.of(bytes)..[10] ^= 1;
    expect(await TranslationModels.verifiedManifest(changed, sig, pub), isNull);
    final List<int> other =
        (await (await ed.newKeyPair()).extractPublicKey()).bytes;
    expect(await TranslationModels.verifiedManifest(bytes, sig, other), isNull);
    expect(
      await TranslationModels.verifiedManifest(bytes, 'nope', pub),
      isNull,
    );
  });

  test("the engine's registry points at the app-only origin", () {
    final List<Map<String, Object?>> reg = engineRegistry(<TranslationModel>[
      m.models['en-he']!,
    ]);
    final Map<String, Object?> files =
        reg.single['files']! as Map<String, Object?>;
    expect(
      (files['model']! as Map<String, String>)['name'],
      'https://translate.zt/models/en-he/model.enhe.intgemm.alphas.bin',
    );
    expect(
      (files['config']! as Map<String, String>)['gemm-precision'],
      'int8shiftAlphaAll',
    );
  });

  group('page language', () {
    test('declared language wins', () {
      expect(detectLanguage('he-IL', ''), 'he');
      expect(detectLanguage('iw', ''), 'he');
      expect(detectLanguage('zh-TW', ''), 'zh_hant');
      expect(detectLanguage('zh-CN', ''), 'zh');
      expect(detectLanguage('fr', 'Hello there'), 'fr');
    });

    test('otherwise guessed from the letters', () {
      expect(
        detectLanguage('', 'שלום עולם, זהו דף בעברית עם הרבה מילים'),
        'he',
      );
      expect(
        detectLanguage('', 'Привет, мир! Это страница на русском языке'),
        'ru',
      );
      expect(detectLanguage('', 'これは日本語のページです。漢字とかなを使います。'), 'ja');
      expect(
        detectLanguage('', 'This is an English page with many words'),
        isNull,
      );
      expect(detectLanguage('', 'short'), isNull);
    });
  });
}
