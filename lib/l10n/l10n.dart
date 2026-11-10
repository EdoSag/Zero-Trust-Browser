import 'package:flutter/widgets.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/generated/app_l10n.dart';

export 'package:zerotrust_browser/l10n/generated/app_l10n.dart';

/// `context.l10n.newTab`: the app's texts in the app's language. The
/// English and Hebrew texts live in tool/l10n_strings.py.
extension L10nContext on BuildContext {
  AppL10n get l10n => AppL10n.of(this);
}

/// Labels for values the settings hold.
extension L10nLabels on AppL10n {
  String historyLabel(int? days) => switch (days) {
    0 => historyNone,
    null => forever,
    7 => oneWeek,
    30 => oneMonth,
    90 => threeMonths,
    365 => oneYear,
    final int d => nDays(d),
  };

  String closeTabsLabel(int? days) => switch (days) {
    null => never,
    1 => afterDay,
    7 => afterWeek,
    14 => afterTwoWeeks,
    30 => afterMonth,
    final int d => afterDays(d),
  };

  /// "Camera", for a list or a title.
  String permissionLabel(String kind) => switch (kind) {
    SitePermission.camera => permCamera,
    SitePermission.microphone => permMicrophone,
    SitePermission.location => permLocation,
    _ => kind,
  };

  /// "camera and microphone", for the question a site's request asks.
  String permissionPhrase(List<String> kinds) {
    final List<String> words = <String>[
      for (final String k in kinds)
        switch (k) {
          SitePermission.camera => permWhatCamera,
          SitePermission.microphone => permWhatMicrophone,
          SitePermission.location => permWhatLocation,
          _ => k,
        },
    ];
    if (words.isEmpty) return '';
    String out = words.first;
    for (int i = 1; i < words.length; i++) {
      out = i == words.length - 1
          ? listAnd(out, words[i])
          : listComma(out, words[i]);
    }
    return out;
  }

  /// Human file size: 1.2 MB, 340 KB, 12 bytes.
  String fileSize(int bytes) {
    if (bytes < 1000) return sizeBytes(bytes);
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / 1000 / 1000).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1000 / 1000 / 1000).toStringAsFixed(1)} GB';
  }
}
