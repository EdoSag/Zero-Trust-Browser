import 'package:zerotrust_browser/browser/address.dart';
import 'package:zerotrust_browser/browser/clean_url.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// Hands the synced settings to the web engine: protection, scripts, text
/// size and dark pages.
Future<void> applySettings(BrowserEngine engine, BrowserSettings s) async {
  await engine.setPrivacy(
    blockTrackers: s.blockTrackers,
    httpsOnly: s.httpsOnly,
    allowedSites: s.allowedSites,
    hideElements: s.hideElements,
    fingerprinting: s.fingerprinting,
    javascriptOff: s.javascriptOff,
    stripTracking: s.stripTracking,
  );
  await engine.setDisplay(textZoom: s.textZoom, darkPages: s.darkPages);
}

/// [url] as it should be copied or shared: without tracking tags, unless
/// that is off or the user turned protection off for the site.
String shareableUrl(String url, BrowserSettings s) {
  if (!s.stripTracking) return url;
  final String clean = cleanUrl(url);
  if (clean == url) return url;
  final String host = hostOf(clean);
  for (final String site in s.allowedSites) {
    if (host == site || host.endsWith('.$site')) return url;
  }
  return clean;
}
