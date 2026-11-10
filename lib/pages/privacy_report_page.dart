import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/l10n/l10n.dart';
import 'package:zerotrust_browser/widgets/address_text.dart';
import 'package:zerotrust_browser/widgets/site_icon.dart';

/// How many trackers and ads were blocked this week, day by day, and on
/// which sites.
class PrivacyReportPage extends ConsumerStatefulWidget {
  const PrivacyReportPage({super.key});

  @override
  ConsumerState<PrivacyReportPage> createState() => _PrivacyReportPageState();
}

class _PrivacyReportPageState extends ConsumerState<PrivacyReportPage> {
  @override
  void initState() {
    super.initState();
    // Show what was blocked up to now, not up to the last save.
    ref.read(privacyReportRecorderProvider).flush().ignore();
  }

  Future<void> _clear() async {
    final AppL10n l = context.l10n;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await ref.read(privacyReportRecorderProvider).clear();
    messenger.showSnackBar(SnackBar(content: Text(l.reportCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BrowserSettings s = ref.watch(browserSettingsProvider);
    final DateTime now = DateTime.now();
    final ReportSummary r = ReportSummary.of(
      ref.watch(privacyReportsProvider).value ?? const <PrivacyReport>[],
      now: now,
    );
    final List<String> weekdays = MaterialLocalizations.of(
      context,
    ).narrowWeekdays;
    final int highest = r.lastDays.fold<int>(
      1,
      (int a, int b) => b > a ? b : a,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.privacyReport),
        actions: <Widget>[
          if (r.month > 0)
            IconButton(
              tooltip: l.reportClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clear,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          if (!s.privacyReport)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l.reportOff),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.shield_outlined, size: 40, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(l.reportWeek(r.week), style: text.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // One bar per day, today last.
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < r.lastDays.length; i++)
                  Expanded(
                    child: _DayBar(
                      count: r.lastDays[i],
                      share: r.lastDays[i] / highest,
                      label: i == r.lastDays.length - 1
                          ? l.today
                          : weekdays[DateTime(
                                  now.year,
                                  now.month,
                                  now.day - (r.lastDays.length - 1 - i),
                                ).weekday %
                                7],
                      today: i == r.lastDays.length - 1,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.reportMonth(PrivacyReport.keepDays, r.month),
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (r.month == 0)
            Text(l.reportEmpty, style: text.bodyMedium)
          else if (r.topSites.isNotEmpty) ...<Widget>[
            Text(l.reportTopSites, style: text.titleSmall),
            const SizedBox(height: 4),
            for (final MapEntry<String, int> site in r.topSites)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SiteIcon(url: 'https://${site.key}'),
                title: AddressText(site.key),
                trailing: Text(
                  l.reportCountOnSite(site.value),
                  style: text.bodyMedium,
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text(
            s.historyDays == 0 ? l.reportNoSites : l.reportNote,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.count,
    required this.share,
    required this.label,
    required this.today,
  });

  final int count;

  /// 0..1 of the tallest bar.
  final double share;
  final String label;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $count',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text(
            count > 9999 ? '${count ~/ 1000}k' : '$count',
            maxLines: 1,
            style: text.labelSmall,
          ),
          const SizedBox(height: 4),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: count == 0 ? 0.02 : share.clamp(0.04, 1.0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: today ? scheme.primary : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: text.labelSmall?.copyWith(
              fontWeight: today ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}
