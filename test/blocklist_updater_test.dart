import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/blocklist_updater.dart';

void main() {
  // A small list signed with the real release key by the same command the
  // weekly workflow uses (openssl pkeyutl -sign -rawin).
  final List<int> gz = File(
    'test/fixtures/blocklist-sample.txt.gz',
  ).readAsBytesSync();
  final String sig = File(
    'test/fixtures/blocklist-sample.txt.gz.sig',
  ).readAsStringSync().trim();
  final List<int> key = base64.decode(blocklistPublicKey);

  test('a list signed with the release key is accepted', () async {
    final String? text = await BlocklistUpdater.verifiedList(gz, sig, key);
    expect(text, isNotNull);
    expect(text, startsWith('# ZT Browser blocklist, format 1.'));
    expect(BlocklistUpdater.listDate(text!), matches(r'^\d{4}-\d{2}-\d{2}T'));
  });

  test('a changed file is refused', () async {
    final List<int> changed = <int>[...gz];
    changed[changed.length ~/ 2] ^= 1;
    expect(await BlocklistUpdater.verifiedList(changed, sig, key), isNull);
  });

  test('another key, or a bad signature, is refused', () async {
    final List<int> other = List<int>.filled(32, 7);
    expect(await BlocklistUpdater.verifiedList(gz, sig, other), isNull);
    expect(await BlocklistUpdater.verifiedList(gz, 'not base64!', key), isNull);
    expect(
      await BlocklistUpdater.verifiedList(gz, base64.encode(<int>[1, 2]), key),
      isNull,
    );
  });

  test('the bundled list carries a date the engine can compare', () {
    final String bundled = File(
      'assets/blocklist/blocklist.txt',
    ).readAsStringSync();
    expect(BlocklistUpdater.listDate(bundled), isNotNull);
    for (final String section in <String>[
      '!hosts',
      '!hide',
      '!hide-off',
      '!site-hide',
    ]) {
      expect(bundled, contains('\n$section\n'));
    }
  });
}
