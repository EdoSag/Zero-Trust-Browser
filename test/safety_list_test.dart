import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/download_check.dart';
import 'package:zerotrust_browser/browser/safety_list.dart';
import 'package:zerotrust_browser/pages/download_sheet.dart';

/// B-1: the phishing and malware list is only used when it is signed with
/// the app's key and really is a safety list.
void main() {
  late SimpleKeyPair keys;
  late List<int> publicKey;

  setUpAll(() async {
    keys = await Ed25519().newKeyPair();
    publicKey = (await keys.extractPublicKey()).bytes;
  });

  List<int> list({String header = safetyListHeader}) {
    final List<int> text = utf8.encode(
      '$header\n# list-date: 2026-11-22T05:23\n# phishing: 1\n# malware: 0\n\n',
    );
    return <int>[...text, 1, 2, 3, 4, 5, 6, 7, 8];
  }

  Future<String> sign(List<int> data) async =>
      base64.encode((await Ed25519().sign(data, keyPair: keys)).bytes);

  test('a signed list is accepted, bytes and all', () async {
    final List<int> raw = list();
    final List<int> gz = gzip.encode(raw);
    final List<int>? got = await SafetyListUpdater.verifiedList(
      gz,
      await sign(gz),
      publicKey,
    );
    expect(got, raw);
    expect(SafetyListUpdater.listDate(got!), '2026-11-22T05:23');
  });

  test('a changed file is refused', () async {
    final List<int> gz = gzip.encode(list());
    final String sig = await sign(gz);
    final List<int> changed = gzip.encode(<int>[...list(), 9]);
    expect(
      await SafetyListUpdater.verifiedList(changed, sig, publicKey),
      isNull,
    );
  });

  test('another key is refused', () async {
    final List<int> gz = gzip.encode(list());
    final SimpleKeyPair other = await Ed25519().newKeyPair();
    final String sig = base64.encode(
      (await Ed25519().sign(gz, keyPair: other)).bytes,
    );
    expect(await SafetyListUpdater.verifiedList(gz, sig, publicKey), isNull);
  });

  test('a signed file that is not a safety list is refused', () async {
    final List<int> gz = gzip.encode(
      list(header: '# ZT Browser blocklist, format 1.'),
    );
    expect(
      await SafetyListUpdater.verifiedList(gz, await sign(gz), publicKey),
      isNull,
    );
  });

  test('a broken signature is refused', () async {
    final List<int> gz = gzip.encode(list());
    expect(
      await SafetyListUpdater.verifiedList(gz, 'not base64!', publicKey),
      isNull,
    );
    expect(await SafetyListUpdater.verifiedList(gz, 'AAAA', publicKey), isNull);
  });

  test('a file from a dangerous site gets a warning', () {
    const DownloadRequest r = DownloadRequest(
      requestId: 1,
      name: 'invoice.pdf',
      mime: 'application/pdf',
      size: 1000,
      url: 'https://bad.example/invoice.pdf',
      dangerousSite: true,
    );
    expect(r.warnings, contains(DownloadWarning.dangerousSite));
    const DownloadRequest ok = DownloadRequest(
      requestId: 2,
      name: 'invoice.pdf',
      mime: 'application/pdf',
      size: 1000,
      url: 'https://good.example/invoice.pdf',
    );
    expect(ok.warnings, isEmpty);
  });
}
