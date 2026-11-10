import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/reader.dart';

void main() {
  test('no article without content', () {
    expect(Article.fromJson(null), isNull);
    expect(
      Article.fromJson(<String, Object?>{'title': 'x', 'content': ' '}),
      isNull,
    );
  });

  test('reader page blocks scripts and escapes the title', () {
    final Article a = Article.fromJson(<String, Object?>{
      'title': '<script>alert(1)</script> & news',
      'content': '<p>Body</p>',
      'byline': 'Dana',
      'lang': 'he" onload="x',
      'dir': 'rtl',
    })!;
    final String html = readerHtml(a, url: 'https://news.example/a?b=1&c=2');
    expect(html, isNot(contains('<script>alert')));
    expect(html, contains("default-src 'none'"));
    expect(html, contains('&lt;script&gt;'));
    expect(html, contains('<p>Body</p>'));
    expect(html, contains('dir="rtl"'));
    // A strange language tag falls back to English.
    expect(html, contains('lang="en"'));
    expect(html, contains('href="https://news.example/a?b=1&amp;c=2"'));
  });

  test('a saved copy says so', () {
    final Article a = Article.fromJson(<String, Object?>{
      'title': 'T',
      'content': '<p>x</p>',
    })!;
    expect(
      readerHtml(a, url: 'https://a.org', saved: true),
      contains('Saved copy'),
    );
    expect(readerHtml(a, url: 'https://a.org'), isNot(contains('Saved copy')));
  });
}
