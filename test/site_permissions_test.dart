import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_browser/browser/site_permissions.dart';
import 'package:zerotrust_browser/data/models.dart';

void main() {
  const String cam = SitePermission.camera;
  const String mic = SitePermission.microphone;
  const String loc = SitePermission.location;

  test('nothing remembered: ask about everything', () {
    final PermissionDecision d = decidePermission(
      const BrowserSettings(),
      'meet.example.com',
      <String>[cam, mic],
      private: false,
    );
    expect(d.allowed, isEmpty);
    expect(d.ask, <String>[cam, mic]);
  });

  test('remembered allows are granted, the rest asked', () {
    final BrowserSettings s = const BrowserSettings().withPermission(
      'Meet.Example.com',
      cam,
      true,
    );
    final PermissionDecision d = decidePermission(
      s,
      'meet.example.com',
      <String>[cam, mic],
      private: false,
    );
    expect(d.allowed, <String>{cam});
    expect(d.ask, <String>[mic]);
  });

  test('one remembered block refuses the whole request at once', () {
    final BrowserSettings s = const BrowserSettings()
        .withPermission('meet.example.com', cam, true)
        .withPermission('meet.example.com', mic, false);
    final PermissionDecision d = decidePermission(
      s,
      'meet.example.com',
      <String>[cam, mic],
      private: false,
    );
    expect(d.allowed, isEmpty);
    expect(d.ask, isEmpty);
  });

  test('private tabs ask even when allowed, but keep blocks', () {
    final BrowserSettings s = const BrowserSettings()
        .withPermission('maps.example', loc, true)
        .withPermission('ads.example', loc, false);
    expect(
      decidePermission(s, 'maps.example', <String>[loc], private: true).ask,
      <String>[loc],
    );
    final PermissionDecision blocked = decidePermission(
      s,
      'ads.example',
      <String>[loc],
      private: true,
    );
    expect(blocked.ask, isEmpty);
    expect(blocked.allowed, isEmpty);
  });

  test('forgetting the last answer removes the site', () {
    final BrowserSettings s = const BrowserSettings()
        .withPermission('a.example', cam, true)
        .withPermission('a.example', cam, null);
    expect(s.sitePermissions, isEmpty);
  });
}
