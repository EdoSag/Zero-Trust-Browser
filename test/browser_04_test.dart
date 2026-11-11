import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/cookie_auto_clear.dart';
import 'package:zerotrust_browser/browser/filter_lists.dart';
import 'package:zerotrust_browser/browser/read_aloud.dart';
import 'package:zerotrust_browser/browser/zt_apps.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  final DateTime at = DateTime(2026, 11, 11, 12);

  group('cookie auto-clear (B24)', () {
    test('keeps hosts whose site is still open', () {
      expect(
        hostsToClear(
          <String>['mail.example.com', 'news.org', 'ynet.co.il'],
          <String>['www.example.com'],
          const <String>[],
        ),
        <String>['news.org', 'ynet.co.il'],
      );
    });

    test('skips sites kept signed in', () {
      expect(
        hostsToClear(
          <String>['accounts.bank.co.uk', 'tracker.net'],
          const <String>[],
          <String>['Bank.co.uk'],
        ),
        <String>['tracker.net'],
      );
    });
  });

  group('hosts and sites', () {
    test('siteOf matches the engine rule', () {
      expect(siteOf('a.b.example.com'), 'example.com');
      expect(siteOf('www.bbc.co.uk'), 'bbc.co.uk');
      expect(siteOf('example.com.'), 'example.com');
      expect(siteOf('localhost'), 'localhost');
    });

    test('cleanHostRule accepts what people paste', () {
      expect(
        cleanHostRule('https://Ads.Example.com/path?q=1'),
        'ads.example.com',
      );
      expect(cleanHostRule('*.tracker.net'), 'tracker.net');
      expect(cleanHostRule('||ads.example.com^'), 'ads.example.com');
      expect(cleanHostRule('cdn.site.io:8443'), 'cdn.site.io');
      expect(cleanHostRule('not a host'), isNull);
      expect(cleanHostRule('localhost'), isNull);
      expect(cleanHostRule(''), isNull);
    });
  });

  group('filter lists (B30)', () {
    test('reads hosts files, domain lists and AdBlock host rules', () {
      const String text = '''
# comment
! AdBlock comment
[Adblock Plus 2.0]
0.0.0.0 ads.example.com
127.0.0.1 track.example.net # inline comment
0.0.0.0 localhost
plain.example.org
||rules.example.com^
||third.example.com^\$third-party
||path.example.com/ads
@@||allowed.example.com^
example.com##.banner
||opts.example.com^\$script
''';
      final Set<String> hosts = parseFilterList(text);
      expect(hosts, <String>{
        'ads.example.com',
        'track.example.net',
        'plain.example.org',
        'rules.example.com',
        'third.example.com',
      });
    });

    test('stops at the limit', () {
      final String text = List<String>.generate(
        50,
        (int i) => 'h$i.example.com',
      ).join('\n');
      expect(parseFilterList(text, max: 10), hasLength(10));
    });
  });

  group('read aloud (B27)', () {
    test('splits on blocks, decodes entities, starts with the title', () {
      final List<String> parts = speechParts(
        '<h1>Head</h1><p>One &amp; two.</p><p>  </p><p>Three&nbsp;four</p>',
        title: 'Title',
      );
      expect(parts.first, 'Title');
      expect(parts, contains('One & two.'));
      expect(parts.last, 'Three four');
      expect(parts.where((String p) => p.trim().isEmpty), isEmpty);
    });

    test('long paragraphs break at sentence ends', () {
      final String para = List<String>.filled(
        40,
        'This is a sentence.',
      ).join(' ');
      final List<String> parts = speechParts('<p>$para</p>', maxLength: 100);
      expect(parts.length, greaterThan(1));
      for (final String p in parts) {
        expect(p.length, lessThanOrEqualTo(100));
        expect(p.endsWith('.'), isTrue);
      }
    });
  });

  group('other ZT apps (B25)', () {
    test('phone number from a tel: link', () {
      expect(phoneFromTel('tel:+972-3-555%201234'), '+972-3-555 1234');
      expect(phoneFromTel('TEL:050123;ext=2'), '050123');
      expect(phoneFromTel('tel:'), isNull);
      expect(phoneFromTel('https://x.com'), isNull);
      expect(phoneFromTel(null), isNull);
    });

    test('note text puts the selection first', () {
      expect(
        noteText(title: 'Page', url: 'https://a.org', selection: ' quote '),
        'quote\n\nPage\nhttps://a.org',
      );
      expect(
        noteText(title: 'https://a.org', url: 'https://a.org'),
        'https://a.org',
      );
    });
  });

  group('models', () {
    test('bookmarks: ordered ones first, then newest', () {
      Bookmark b(String id, {double? pos, int day = 1}) => Bookmark(
        id: id,
        url: 'https://$id.org',
        title: id,
        createdAt: DateTime(2026, 11, day),
        position: pos,
      );
      final List<Bookmark> list = <Bookmark>[
        b('old', day: 1),
        b('second', pos: 2),
        b('new', day: 5),
        b('first', pos: 1),
      ]..sort(Bookmark.compare);
      expect(list.map((Bookmark x) => x.id), <String>[
        'first',
        'second',
        'new',
        'old',
      ]);
    });

    test('bookmark folder and position round trip; blank folder is none', () {
      final Bookmark x = Bookmark(
        id: 'b',
        url: 'https://a.org',
        title: 'A',
        createdAt: at,
        folder: 'Work',
        position: 3.5,
      );
      final Bookmark back = Bookmark.fromJson('b', x.toJson(), at);
      expect(back.folder, 'Work');
      expect(back.position, 3.5);
      final Bookmark blank = Bookmark.fromJson('c', <String, Object?>{
        'url': 'https://b.org',
        'folder': '  ',
      }, at);
      expect(blank.folder, isNull);
      expect(back.copyWith(folder: () => null).folder, isNull);
    });

    test('sent tab round trip', () {
      final SentTab t = SentTab(
        id: 's',
        url: 'https://a.org',
        title: 'A',
        fromDevice: 'd1',
        fromName: 'Pixel',
        toDevice: 'd2',
        sentAt: at,
      );
      final SentTab back = SentTab.fromJson('s', t.toJson(), at);
      expect(back.url, t.url);
      expect(back.fromName, 'Pixel');
      expect(back.toDevice, 'd2');
      expect(back.sentAt, at);
    });

    test('0.4 settings round trip and defaults', () {
      final BrowserSettings empty = BrowserSettings.fromJson(
        'x',
        const <String, Object?>{},
        at,
      );
      expect(empty.autoClearCookies, isFalse);
      expect(empty.privateNoScreenshots, isTrue);
      expect(empty.privateHideRecents, isTrue);
      expect(empty.privateLock, isFalse);
      expect(empty.backgroundPlay, isTrue);
      expect(empty.readAloudRate, 1.0);

      final BrowserSettings s = empty.copyWith(
        autoClearCookies: true,
        keepSignedIn: <String>['bank.com'],
        privateLock: true,
        privateNoScreenshots: false,
        blockedHosts: <String>['ads.example.com'],
        unblockedHosts: <String>['ok.example.com'],
        filterLists: <String>['https://lists.example/hosts.txt'],
        bookmarkFolders: <String>['Work', 'Fun'],
        backgroundPlay: false,
        readAloudRate: 1.5,
      );
      final BrowserSettings back = BrowserSettings.fromJson(
        'x',
        s.toJson(),
        at,
      );
      expect(back.autoClearCookies, isTrue);
      expect(back.keepSignedIn, <String>['bank.com']);
      expect(back.keepsSignedIn('bank.com'), isTrue);
      expect(back.privateLock, isTrue);
      expect(back.privateNoScreenshots, isFalse);
      expect(back.blockedHosts, <String>['ads.example.com']);
      expect(back.unblockedHosts, <String>['ok.example.com']);
      expect(back.filterLists, <String>['https://lists.example/hosts.txt']);
      expect(back.bookmarkFolders, <String>['Work', 'Fun']);
      expect(back.backgroundPlay, isFalse);
      expect(back.readAloudRate, 1.5);

      final BrowserSettings bad = BrowserSettings.fromJson(
        'x',
        <String, Object?>{'readAloudRate': 9},
        at,
      );
      expect(bad.readAloudRate, 1.0);
    });
  });
}
