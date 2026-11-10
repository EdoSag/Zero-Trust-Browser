import 'package:zerotrust_browser/data/models.dart';

/// What to do with a site's request for camera, microphone or location.
class PermissionDecision {
  const PermissionDecision({required this.allowed, required this.ask});

  /// Kinds to grant without asking (remembered "allow").
  final Set<String> allowed;

  /// Kinds to ask the user about. Empty means answer now with [allowed].
  final List<String> ask;
}

/// Uses remembered answers; the rest is asked. A remembered "block" for
/// any kind refuses the whole request (sites ask for camera and microphone
/// together, and get both or neither). Private tabs use remembered blocks
/// but never remembered allows, like other browsers' private modes.
PermissionDecision decidePermission(
  BrowserSettings s,
  String host,
  List<String> kinds, {
  required bool private,
}) {
  final Set<String> allowed = <String>{};
  final List<String> ask = <String>[];
  for (final String kind in kinds) {
    final bool? remembered = s.permissionFor(host, kind);
    if (remembered == false) {
      return const PermissionDecision(allowed: <String>{}, ask: <String>[]);
    }
    if (remembered == true && !private) {
      allowed.add(kind);
    } else {
      ask.add(kind);
    }
  }
  return PermissionDecision(allowed: allowed, ask: ask);
}

/// "your camera and microphone", for the question.
String permissionPhrase(List<String> kinds) {
  final List<String> words = <String>[
    for (final String k in kinds)
      switch (k) {
        SitePermission.camera => 'camera',
        SitePermission.microphone => 'microphone',
        SitePermission.location => 'location',
        _ => k,
      },
  ];
  if (words.isEmpty) return '';
  if (words.length == 1) return 'your ${words.first}';
  return 'your ${words.sublist(0, words.length - 1).join(', ')} and '
      '${words.last}';
}
