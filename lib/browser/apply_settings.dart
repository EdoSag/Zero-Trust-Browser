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
  );
  await engine.setDisplay(textZoom: s.textZoom, darkPages: s.darkPages);
}
