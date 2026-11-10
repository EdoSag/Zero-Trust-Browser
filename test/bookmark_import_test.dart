import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/bookmark_import.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  test('reads a Chrome export with nested folders', () {
    const String chrome = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="1" LAST_MODIFIED="2" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://news.example.org/" ADD_DATE="1700000000">News &amp; more</A>
        <DT><H3 ADD_DATE="1">Travel</H3>
        <DL><p>
            <DT><A HREF="https://maps.example.com/route?a=1&amp;b=2" ADD_DATE="1700000001">Route</A>
            <DT><H3>Israel</H3>
            <DL><p>
                <DT><A HREF="https://example.co.il/">אתר בעברית</A>
            </DL><p>
        </DL><p>
        <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
    </DL><p>
    <DT><H3>Other bookmarks</H3>
    <DL><p>
        <DT><A HREF="http://plain.example.net">Plain</A>
    </DL><p>
</DL><p>
''';
    final List<Bookmark> b = parseBookmarksHtml(chrome);
    expect(b.map((Bookmark x) => x.url), <String>[
      'https://news.example.org/',
      'https://maps.example.com/route?a=1&b=2',
      'https://example.co.il/',
      'http://plain.example.net',
    ]);
    expect(b[0].title, 'News & more');
    expect(b[0].folder, isNull);
    expect(b[0].createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(b[1].folder, 'Travel');
    expect(b[2].folder, 'Travel / Israel');
    expect(b[2].title, 'אתר בעברית');
    expect(b[3].folder, isNull);
  });

  test('reads a Firefox export (menu, toolbar, unfiled)', () {
    const String firefox = '''
<DL><p>
    <DT><H3 ADD_DATE="1">Bookmarks Menu</H3>
    <DL><p>
        <DT><A HREF="https://www.mozilla.org/" ADD_DATE="1" ICON="data:image/png;base64,AAA">Mozilla</A>
        <DT><H3>Recipes</H3>
        <DL><p>
            <DT><A HREF='https://soup.example/'>Soup</A>
        </DL><p>
    </DL><p>
    <DT><H3 UNFILED_BOOKMARKS_FOLDER="true">Other Bookmarks</H3>
    <DL><p>
        <DT><A HREF="https://a.example/">A</A>
    </DL><p>
</DL>
''';
    final List<Bookmark> b = parseBookmarksHtml(firefox);
    expect(b, hasLength(3));
    expect(b[0].folder, isNull);
    expect(b[1].folder, 'Recipes');
    expect(b[1].url, 'https://soup.example/');
    expect(b[2].folder, isNull);
  });

  test('gives every bookmark its own id and keeps file order', () {
    final List<Bookmark> b = parseBookmarksHtml(
      '<DL><DT><A HREF="https://a.org">A</A><DT><A HREF="https://b.org">B</A></DL>',
      now: DateTime(2026, 11, 10),
    );
    expect(b[0].id, isNot(b[1].id));
    expect(b[0].createdAt.isAfter(b[1].createdAt), isTrue);
  });

  test('a file without bookmarks gives nothing', () {
    expect(parseBookmarksHtml('<html><body>Hello</body></html>'), isEmpty);
  });
}
