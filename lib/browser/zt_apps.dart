import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// The other Zero-Trust apps ZT Browser hands things to (B25). Everything
/// goes straight from app to app on the phone; nothing is sent anywhere.
abstract final class ZtApps {
  static const String notes = 'dev.sagron.zerotrustnotes';
  static const String tasks = 'dev.sagron.zerotrusttasks';
  static const String phone = 'dev.sagron.zerotrustphone';
  static const String contacts = 'dev.sagron.zerotrustcontacts';

  static const List<String> all = <String>[notes, tasks, phone, contacts];
}

/// Which ZT apps are installed. Checked again each time a menu opens via
/// `ref.invalidate`, so a newly installed app shows up.
final installedZtAppsProvider = FutureProvider<Set<String>>(
  (ref) => ref.read(browserEngineProvider).installedApps(ZtApps.all),
);

/// What goes to ZT Notes for a page: the selected text (quoted) when there
/// is some, then the page's title and address.
String noteText({
  required String title,
  required String url,
  String? selection,
}) {
  final StringBuffer b = StringBuffer();
  final String sel = selection?.trim() ?? '';
  if (sel.isNotEmpty) {
    b
      ..writeln(sel)
      ..writeln();
  }
  if (title.trim().isNotEmpty && title.trim() != url) b.writeln(title.trim());
  b.write(url);
  return b.toString();
}

/// A phone number from a `tel:` link ("tel:+972-3-555%201234" gives
/// "+972-3-555 1234"), or null.
String? phoneFromTel(String? url) {
  if (url == null || !url.toLowerCase().startsWith('tel:')) return null;
  String n = url.substring(4);
  final int q = n.indexOf(RegExp('[?;]'));
  if (q >= 0) n = n.substring(0, q);
  try {
    n = Uri.decodeComponent(n);
  } on ArgumentError {
    // Keep as is.
  }
  n = n.trim();
  return RegExp(r'\d').hasMatch(n) ? n : null;
}
