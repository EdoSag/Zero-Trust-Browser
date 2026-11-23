import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/engine/engine.dart';

/// Shows tab [tabId]'s native WebView. Disposing this widget only takes
/// the page off screen; the tab keeps running until it's closed.
class TabView extends StatelessWidget {
  const TabView({super.key, required this.tabId});

  final String tabId;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return WindowsTabView(tabId: tabId);
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('Pages open on Android and Windows.'));
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

/// Windows: the page is a WebView2 window laid over the app. This widget
/// keeps the space for it and, after every frame, tells the engine where
/// that space is. The page hides while another screen, sheet, menu or
/// dialog is on top, since a native window would cover them.
class WindowsTabView extends ConsumerStatefulWidget {
  const WindowsTabView({super.key, required this.tabId});

  final String tabId;

  @override
  ConsumerState<WindowsTabView> createState() => _WindowsTabViewState();
}

class _WindowsTabViewState extends ConsumerState<WindowsTabView> {
  Rect? _sent;
  bool _sentVisible = false;
  late final BrowserEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(browserEngineProvider);
    _watch();
  }

  @override
  void didUpdateWidget(WindowsTabView old) {
    super.didUpdateWidget(old);
    if (old.tabId != widget.tabId) {
      _engine.setTabBounds(old.tabId, Rect.zero, visible: false);
      _sent = null;
    }
  }

  @override
  void dispose() {
    _engine.setTabBounds(widget.tabId, _sent ?? Rect.zero, visible: false);
    super.dispose();
  }

  /// Checks the place after each frame the app draws (no extra frames).
  void _watch() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _report();
      _watch();
    });
  }

  void _report() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final Rect rect = windowsTabRect(
      box.localToGlobal(Offset.zero),
      box.size,
      ratio,
    );
    final bool visible =
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (rect == _sent && visible == _sentVisible) return;
    _sent = rect;
    _sentVisible = visible;
    _engine.setTabBounds(widget.tabId, rect, visible: visible);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// The page's place in the window, in whole physical pixels.
@visibleForTesting
Rect windowsTabRect(Offset topLeft, Size size, double ratio) {
  final double left = (topLeft.dx * ratio).roundToDouble();
  final double top = (topLeft.dy * ratio).roundToDouble();
  final double right = ((topLeft.dx + size.width) * ratio).roundToDouble();
  final double bottom = ((topLeft.dy + size.height) * ratio).roundToDouble();
  return Rect.fromLTRB(left, top, right, bottom);
}
