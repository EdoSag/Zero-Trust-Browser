import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The tab [step] places from [currentId] in [ids] (+1 the next, -1 the
/// one before), or null when there is none that way.
String? neighborTab(List<String> ids, String? currentId, int step) {
  final int at = currentId == null ? -1 : ids.indexOf(currentId);
  if (at < 0) return null;
  final int to = at + step;
  if (to < 0 || to >= ids.length) return null;
  return ids[to];
}

/// Which way a sideways swipe moves through the tabs: toward the start of
/// the line (left in English, right in Hebrew) is the next tab, like
/// turning a page.
int swipeStep(double dx, TextDirection direction) {
  final bool towardStart = direction == TextDirection.ltr ? dx < 0 : dx > 0;
  return towardStart ? 1 : -1;
}

/// B28: swipe gestures on the browser's bars. Sideways switches to the tab
/// beside this one; up (on the bottom bar) shows all tabs. The bar follows
/// the finger, and springs back when there is no tab that way.
class TabSwipe extends StatefulWidget {
  const TabSwipe({
    super.key,
    required this.child,
    required this.enabled,
    required this.canSwitch,
    required this.onSwitch,
    this.onSwipeUp,
  });

  final Widget child;

  /// Off in the settings, or while typing in the address bar.
  final bool enabled;

  /// Whether there is a tab [step] places away.
  final bool Function(int step) canSwitch;
  final ValueChanged<int> onSwitch;

  /// Swiping up, null where it does nothing.
  final VoidCallback? onSwipeUp;

  /// How far (logical pixels) or fast (pixels a second) a swipe must go.
  static const double distance = 72;
  static const double speed = 700;

  @override
  State<TabSwipe> createState() => _TabSwipeState();
}

class _TabSwipeState extends State<TabSwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dx = _from * (1 - _back.value)));

  double _dx = 0;
  double _from = 0;
  double _dy = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _back.stop();
    final double raw = _dx + d.delta.dx;
    final int step = swipeStep(raw, Directionality.of(context));
    // No tab that way: the bar only gives a little.
    final double next = widget.canSwitch(step) ? raw : _dx + d.delta.dx / 4;
    setState(() => _dx = next.clamp(-160.0, 160.0));
  }

  void _end(DragEndDetails d) {
    final double v = d.primaryVelocity ?? 0;
    final double dx = _dx.abs() >= 1 ? _dx : v;
    final int step = swipeStep(dx, Directionality.of(context));
    final bool far = _dx.abs() >= TabSwipe.distance;
    final bool fast = v.abs() >= TabSwipe.speed && v.sign == dx.sign;
    if ((far || fast) && widget.canSwitch(step)) {
      HapticFeedback.selectionClick();
      widget.onSwitch(step);
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final VoidCallback? up = widget.onSwipeUp;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () {
        _from = _dx;
        _back.forward(from: 0);
      },
      onVerticalDragStart: up == null ? null : (_) => _dy = 0,
      onVerticalDragUpdate: up == null ? null : (d) => _dy += d.delta.dy,
      onVerticalDragEnd: up == null
          ? null
          : (DragEndDetails d) {
              final double v = d.primaryVelocity ?? 0;
              if (_dy <= -40 || v <= -TabSwipe.speed) {
                HapticFeedback.selectionClick();
                up();
              }
            },
      child: Transform.translate(
        offset: Offset(_dx, 0),
        child: Opacity(
          opacity: (1 - _dx.abs() / 320).clamp(0.5, 1.0),
          child: widget.child,
        ),
      ),
    );
  }
}
