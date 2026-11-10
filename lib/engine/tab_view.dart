import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows tab [tabId]'s native WebView. Disposing this widget only takes
/// the page off screen; the tab keeps running until it's closed.
class TabView extends StatelessWidget {
  const TabView({super.key, required this.tabId});

  final String tabId;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('Pages open on Android only.'));
    }
    return AndroidView(
      key: ValueKey<String>('tab-$tabId'),
      viewType: 'zt_browser/tab',
      creationParams: <String, Object?>{'tabId': tabId},
      creationParamsCodec: const StandardMessageCodec(),
      // The page gets every touch: scrolling, pinch zoom, long press.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}
