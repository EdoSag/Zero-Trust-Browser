import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zerotrust_browser/browser/search_suggestions.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  test('only searches are sent, never addresses', () {
    expect(SearchSuggestions.shouldAsk('weather tel aviv'), isTrue);
    expect(SearchSuggestions.shouldAsk('מזג אוויר'), isTrue);
    expect(SearchSuggestions.shouldAsk('w'), isFalse);
    expect(SearchSuggestions.shouldAsk('example.com'), isFalse);
    expect(SearchSuggestions.shouldAsk('example.c'), isFalse);
    expect(
      SearchSuggestions.shouldAsk('https://bank.example/account'),
      isFalse,
    );
    expect(SearchSuggestions.shouldAsk('192.168.1.1/admin'), isFalse);
    expect(SearchSuggestions.shouldAsk('localhost/x'), isFalse);
    expect(SearchSuggestions.shouldAsk('a' * 101), isFalse);
  });

  test('reads the OpenSearch format and the phrase format', () {
    expect(
      SearchSuggestions.parse('["we",["weather","web","weather"]]'),
      <String>['weather', 'web'],
    );
    expect(
      SearchSuggestions.parse('[{"phrase":"weather"},{"phrase":"web"}]'),
      <String>['weather', 'web'],
    );
    expect(SearchSuggestions.parse('<html>'), isEmpty);
    expect(SearchSuggestions.parse('{"a":1}'), isEmpty);
    expect(
      SearchSuggestions.parse('["a",["1","2","3","4","5","6","7"]]'),
      hasLength(SearchSuggestions.max),
    );
  });

  test('asks the chosen engine, and nothing for an address', () async {
    final List<Uri> asked = <Uri>[];
    final SearchSuggestions s = SearchSuggestions(
      MockClient((http.Request r) async {
        asked.add(r.url);
        expect(r.headers.containsKey('cookie'), isFalse);
        return http.Response('["cats",["cats and dogs"]]', 200);
      }),
    );
    expect(await s.fetch(SearchEngine.duckDuckGo, 'cats'), <String>[
      'cats and dogs',
    ]);
    expect(asked.single.host, 'duckduckgo.com');
    expect(asked.single.queryParameters['q'], 'cats');

    expect(await s.fetch(SearchEngine.duckDuckGo, 'bank.example'), isEmpty);
    expect(asked, hasLength(1));
  });

  test('an engine without suggestions, or a failure, gives none', () async {
    final SearchSuggestions s = SearchSuggestions(
      MockClient((http.Request r) async => http.Response('no', 500)),
    );
    expect(await s.fetch(SearchEngine.duckDuckGo, 'cats'), isEmpty);
    expect(await s.fetch(SearchEngine.byId('mojeek'), 'cats'), isEmpty);
  });

  test('a custom engine comes from a name and an address with %s', () {
    final SearchEngine e = SearchEngine.fromUser(
      'Wiki',
      'he.wikipedia.org/w/index.php?search=%s',
    )!;
    expect(e.custom, isTrue);
    expect(e.searchUrl('תל אביב').host, 'he.wikipedia.org');
    expect(e.searchUrl('a b').queryParameters['search'], 'a b');
    expect(e.home, 'https://he.wikipedia.org/');
    expect(e.suggestUrl('x'), isNull);
    expect(SearchEngine.fromUser('X', 'example.com/search'), isNull);
    expect(SearchEngine.fromUser('', 'example.com/?q=%s'), isNull);
    expect(SearchEngine.fromUser('X', 'javascript:alert(%s)'), isNull);

    final BrowserSettings s = BrowserSettings(
      searchEngine: e.id,
      customEngines: <SearchEngine>[e],
    );
    final BrowserSettings back = BrowserSettings.fromJson(
      BrowserSettings.itemId,
      s.toJson(),
      DateTime(2026),
    );
    expect(back.engine.name, 'Wiki');
    expect(back.engine.template, e.template);
    // A removed engine falls back to the default.
    expect(
      back.copyWith(customEngines: <SearchEngine>[]).engine.id,
      'duckduckgo',
    );
  });
}
