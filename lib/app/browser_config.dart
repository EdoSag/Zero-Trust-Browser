import 'package:flutter/material.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Browser in the suite. Not in the core's `ZtSuite` list yet, so the other
/// apps don't link to it before it's released.
const ZtSuiteApp browserSuiteApp = ZtSuiteApp(
  appId: 'browser',
  name: 'Browser',
  tagline: 'The web, without trackers',
  icon: Icons.public,
  accent: Color(0xFFF97316), // orange
  androidPackage: 'dev.sagron.zerotrustbrowser',
);

const ZtAppConfig browserAppConfig = ZtAppConfig(
  appId: 'browser',
  displayName: 'Zero-Trust Browser',
  accent: Color(0xFFF97316),
  // Browsing is long reading with few taps; lock after 15 idle minutes
  // until the user picks their own delay in settings.
  autoLockAfter: Duration(minutes: 15),
);
