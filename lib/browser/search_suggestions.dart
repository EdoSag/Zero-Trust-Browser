import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/data/models.dart';

/// Search suggestions from the chosen search engine, while typing.
///
/// Off unless the user turns it on: every few letters typed go to the
/// search engine. Addresses are never sent, nor anything typed in a
/// private tab. The request carries no cookies and comes from the app,
/// not from a web page.
class SearchSuggestions {
  SearchSuggestions([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  static const int max = 5;

  /// Whether [text] is something to ask suggestions for: a few letters of
  /// a search, not an address.
  static bool shouldAsk(String text) {
    final String t = text.trim();
    if (t.length < 2 || t.length > 100) return false;
    if (t.contains('://') || looksLikeAddress(t)) return false;
    // A host being typed ("example.c") or a local path.
    if (!t.contains(' ') && (t.contains('.') || t.contains('/'))) return false;
    return true;
  }

  /// Up to [max] suggestions for [text]; empty on any failure.
  Future<List<String>> fetch(SearchEngine engine, String text) async {
    if (!shouldAsk(text)) return const <String>[];
    final Uri? url = engine.suggestUrl(text.trim());
    if (url == null || url.scheme != 'https') return const <String>[];
    try {
      final http.Response r = await _client
          .get(url, headers: const <String, String>{'Accept': '*/*'})
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200 || r.bodyBytes.length > 64 * 1024) {
        return const <String>[];
      }
      return parse(utf8.decode(r.bodyBytes, allowMalformed: true));
    } on Object {
      return const <String>[];
    }
  }

  /// Reads the OpenSearch suggestions format: `["typed", ["one", "two"]]`.
  /// Also accepts a list of `{"phrase": "one"}` (DuckDuckGo's other form).
  static List<String> parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return const <String>[];
    }
    if (json is! List) return const <String>[];
    final Object? list = json.length >= 2 && json[1] is List ? json[1] : json;
    final List<String> out = <String>[];
    for (final Object? item in list! as List<Object?>) {
      final Object? text = item is Map ? item['phrase'] : item;
      if (text is! String) continue;
      final String t = text.trim();
      if (t.isEmpty || t.length > 200 || out.contains(t)) continue;
      out.add(t);
      if (out.length == max) break;
    }
    return out;
  }
}

final searchSuggestionsProvider = Provider<SearchSuggestions>(
  (ref) => SearchSuggestions(),
);
