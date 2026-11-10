import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  const SearchEngine ddg = SearchEngine.duckDuckGo;

  group('addressOrSearch', () {
    test('opens host names over https', () {
      expect(addressOrSearch('example.com', ddg), 'https://example.com');
      expect(
        addressOrSearch('news.ycombinator.com/item?id=1', ddg),
        'https://news.ycombinator.com/item?id=1',
      );
      expect(
        addressOrSearch('192.168.1.1:8080', ddg),
        'https://192.168.1.1:8080',
      );
    });

    test('keeps a typed scheme', () {
      expect(
        addressOrSearch('http://neverssl.com', ddg),
        'http://neverssl.com',
      );
      expect(addressOrSearch('  https://a.org/x ', ddg), 'https://a.org/x');
    });

    test('searches everything else', () {
      expect(
        addressOrSearch('zero trust apps', ddg),
        'https://duckduckgo.com/?q=zero+trust+apps',
      );
      expect(
        addressOrSearch('flutter', ddg),
        'https://duckduckgo.com/?q=flutter',
      );
      expect(
        addressOrSearch('what is 1.5', ddg),
        startsWith('https://duckduckgo.com/?q='),
      );
    });

    test('empty input goes to the engine home page', () {
      expect(addressOrSearch('   ', ddg), ddg.home);
    });

    test('uses the chosen engine', () {
      expect(
        addressOrSearch('cats & dogs', SearchEngine.byId('startpage')),
        'https://www.startpage.com/do/search?q=cats+%26+dogs',
      );
    });
  });

  group('displayAddress', () {
    test('drops the scheme and www', () {
      expect(displayAddress('https://www.example.com/'), 'example.com');
      expect(displayAddress('https://example.com/a/b?c=1'), 'example.com/a/b');
    });

    test('shows the search words on a results page', () {
      expect(
        displayAddress('https://duckduckgo.com/?q=zero+trust'),
        'zero trust',
      );
    });
  });

  test('sameAddress ignores http vs https and a trailing slash', () {
    expect(sameAddress('http://a.org/', 'https://a.org'), isTrue);
    expect(sameAddress('https://a.org/x', 'https://a.org/y'), isFalse);
  });
}
