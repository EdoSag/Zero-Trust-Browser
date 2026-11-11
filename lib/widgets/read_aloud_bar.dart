import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/engine/engine.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';

/// Read aloud controls (B27), above the toolbar while a page is read:
/// back a paragraph, play or pause, next paragraph, speed, stop.
class ReadAloudBar extends ConsumerWidget {
  const ReadAloudBar({super.key, required this.state});

  final ReadAloudState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final BrowserEngine engine = ref.read(browserEngineProvider);
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool speaking = state.status == 'speaking';
    return Material(
      color: scheme.secondaryContainer,
      child: SizedBox(
        height: 52,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 12),
            Icon(
              Icons.record_voice_over_outlined,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.parts > 0
                    ? l.readAloudProgress(state.part + 1, state.parts)
                    : l.readAloud,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            IconButton(
              tooltip: l.previous,
              icon: const Icon(Icons.skip_previous),
              onPressed: () => engine.readAloudSkip(-1),
            ),
            IconButton(
              tooltip: speaking ? l.pause : l.play,
              icon: Icon(speaking ? Icons.pause : Icons.play_arrow),
              onPressed: speaking
                  ? engine.readAloudPause
                  : engine.readAloudResume,
            ),
            IconButton(
              tooltip: l.next,
              icon: const Icon(Icons.skip_next),
              onPressed: () => engine.readAloudSkip(1),
            ),
            TextButton(
              onPressed: () {
                final List<double> rates = BrowserSettings.readAloudRates;
                final int i = rates.indexOf(s.readAloudRate);
                final double next = rates[(i + 1) % rates.length];
                ref
                    .read(browserDataProvider)
                    .saveSettings(s.copyWith(readAloudRate: next));
                engine.readAloudRate(next);
              },
              child: Text(
                '${s.readAloudRate.toStringAsFixed(s.readAloudRate % 1 == 0 ? 0 : 2).replaceAll(RegExp(r'0$'), '')}×',
                semanticsLabel: l.readAloudSpeed,
                textDirection: TextDirection.ltr,
              ),
            ),
            IconButton(
              tooltip: l.stop,
              icon: const Icon(Icons.close),
              onPressed: engine.readAloudStop,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
