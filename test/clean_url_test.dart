import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/clean_url.dart';

void main() {
  // The same cases check the web engine's copy (LinkCleaner.kt).
  final List<Object?> cases =
      jsonDecode(File('test/fixtures/clean_url_cases.json').readAsStringSync())
          as List<Object?>;

  for (final Object? c in cases) {
    final List<Object?> pair = c! as List<Object?>;
    test('cleans ${pair[0]}', () {
      expect(cleanUrl(pair[0]! as String), pair[1]);
    });
  }

  test('a clean link comes back as the same string', () {
    const String url = 'https://example.com/a?b=1&c=2#top';
    expect(identical(cleanUrl(url), url), isTrue);
  });

  test('cleaning twice changes nothing more', () {
    for (final Object? c in cases) {
      final String once = cleanUrl((c! as List<Object?>)[0]! as String);
      expect(cleanUrl(once), once);
    }
  });

  test('wrappers inside wrappers stop after a few steps', () {
    String url = 'https://example.com/';
    for (int i = 0; i < 6; i++) {
      url = 'https://www.google.com/url?q=${Uri.encodeQueryComponent(url)}';
    }
    expect(cleanUrl(url), startsWith('https://www.google.com/url?q='));
  });

  test('rules are lower case, as the matcher expects', () {
    for (final String p in trackingParams) {
      expect(p, p.toLowerCase());
    }
  });
}
