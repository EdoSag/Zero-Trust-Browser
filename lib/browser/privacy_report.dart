import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';

/// `2026-11-10` for [d] (local time).
String reportDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What was blocked on one day.
class ReportDay {
  const ReportDay({this.total = 0, this.sites = const <String, int>{}});

  /// Trackers and ads blocked, including those counted without a site
  /// (private tabs, or while history is off).
  final int total;

  /// Blocked per site visited (`example.com`).
  final Map<String, int> sites;

  ReportDay plus(ReportDay other) {
    final Map<String, int> merged = <String, int>{...sites};
    for (final MapEntry<String, int> e in other.sites.entries) {
      merged[e.key] = (merged[e.key] ?? 0) + e.value;
    }
    return ReportDay(total: total + other.total, sites: merged);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'total': total,
    'sites': sites,
  };

  static ReportDay fromJson(Object? j) {
    if (j is! Map) return const ReportDay();
    final Map<String, int> sites = <String, int>{};
    final Object? raw = j['sites'];
    if (raw is Map) {
      for (final MapEntry<Object?, Object?> e in raw.entries) {
        if (e.key is String && e.value is int) {
          sites[e.key! as String] = e.value! as int;
        }
      }
    }
    return ReportDay(total: (j['total'] as num?)?.toInt() ?? 0, sites: sites);
  }
}

/// How many trackers and ads one device blocked, per day and site. Kept
/// like history: end-to-end encrypted in the account, one item per device.
class PrivacyReport {
  const PrivacyReport({
    required this.deviceId,
    this.days = const <String, ReportDay>{},
  });

  final String deviceId;

  /// By [reportDay].
  final Map<String, ReportDay> days;

  String get id => 'report-$deviceId';

  /// Days kept.
  static const int keepDays = 28;

  /// Sites kept per day (the ones with most blocked).
  static const int sitesPerDay = 100;

  /// This report plus [added], without days older than [keepDays] and,
  /// when [withSites] is false (history is off), without any site names.
  PrivacyReport merged(
    Map<String, ReportDay> added, {
    required DateTime now,
    bool withSites = true,
  }) {
    final String oldest = reportDay(
      DateTime(now.year, now.month, now.day - (keepDays - 1)),
    );
    final Map<String, ReportDay> next = <String, ReportDay>{};
    for (final String day in <String>{...days.keys, ...added.keys}) {
      if (day.compareTo(oldest) < 0) continue;
      ReportDay d = (days[day] ?? const ReportDay()).plus(
        added[day] ?? const ReportDay(),
      );
      if (!withSites) {
        d = ReportDay(total: d.total);
      } else if (d.sites.length > sitesPerDay) {
        final List<MapEntry<String, int>> top = d.sites.entries.toList()
          ..sort(
            (MapEntry<String, int> a, MapEntry<String, int> b) =>
                b.value.compareTo(a.value),
          );
        d = ReportDay(
          total: d.total,
          sites: Map<String, int>.fromEntries(top.take(sitesPerDay)),
        );
      }
      next[day] = d;
    }
    return PrivacyReport(deviceId: deviceId, days: next);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'days': <String, Object?>{
      for (final MapEntry<String, ReportDay> e in days.entries)
        e.key: e.value.toJson(),
    },
  };

  static PrivacyReport fromJson(String id, Map<String, Object?> j, DateTime _) {
    final Map<String, ReportDay> days = <String, ReportDay>{};
    final Object? raw = j['days'];
    if (raw is Map) {
      for (final MapEntry<Object?, Object?> e in raw.entries) {
        if (e.key is String) {
          days[e.key! as String] = ReportDay.fromJson(e.value);
        }
      }
    }
    return PrivacyReport(
      deviceId:
          j['deviceId'] as String? ??
          (id.startsWith('report-') ? id.substring(7) : id),
      days: days,
    );
  }

  static final ZtCollection<PrivacyReport> collection =
      ZtCollection<PrivacyReport>(
        kind: 'privacy-report',
        fromJson: PrivacyReport.fromJson,
        toJson: (PrivacyReport r) => r.toJson(),
        idOf: (PrivacyReport r) => r.id,
      );
}

/// The numbers the report screen shows, over all the account's devices.
class ReportSummary {
  const ReportSummary({
    required this.lastDays,
    required this.week,
    required this.month,
    required this.topSites,
  });

  /// Blocked on each of the last 7 days, oldest first; today is last.
  final List<int> lastDays;
  final int week;

  /// The last [PrivacyReport.keepDays] days.
  final int month;

  /// Sites with most blocked in the last 7 days, most first.
  final List<MapEntry<String, int>> topSites;

  static ReportSummary of(
    Iterable<PrivacyReport> reports, {
    required DateTime now,
    int sites = 20,
  }) {
    ReportDay all(String day) {
      ReportDay sum = const ReportDay();
      for (final PrivacyReport r in reports) {
        final ReportDay? d = r.days[day];
        if (d != null) sum = sum.plus(d);
      }
      return sum;
    }

    final List<int> lastDays = <int>[];
    ReportDay week = const ReportDay();
    int month = 0;
    for (int ago = PrivacyReport.keepDays - 1; ago >= 0; ago--) {
      final ReportDay d = all(
        reportDay(DateTime(now.year, now.month, now.day - ago)),
      );
      month += d.total;
      if (ago < 7) {
        lastDays.add(d.total);
        week = week.plus(d);
      }
    }
    final List<MapEntry<String, int>> top = week.sites.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return ReportSummary(
      lastDays: lastDays,
      week: week.total,
      month: month,
      topSites: top.length > sites ? top.sublist(0, sites) : top,
    );
  }
}

/// Every device's report, live.
final privacyReportsProvider = StreamProvider<List<PrivacyReport>>((
  ref,
) async* {
  final LocalItemStore store = await ref.watch(ztLocalStoreProvider.future);
  yield* PrivacyReport.collection.watch(store as ZtLocalStore);
});

/// Counts what the blocker stops and saves it now and then, so browsing
/// doesn't write to the account on every blocked request.
class PrivacyReportRecorder {
  PrivacyReportRecorder(this.ref);

  final Ref ref;
  final Map<String, ReportDay> _pending = <String, ReportDay>{};
  Timer? _timer;
  bool _saving = false;

  static const Duration saveEvery = Duration(minutes: 1);

  /// [count] more blocked on [site]. An empty [site] (private tabs) only
  /// adds to the total.
  void add(String site, int count, {DateTime? now}) {
    if (count <= 0) return;
    final BrowserSettings s = ref.read(browserSettingsProvider);
    if (!s.privacyReport) return;
    final bool named = site.isNotEmpty && s.historyDays != 0;
    final String day = reportDay(now ?? DateTime.now());
    _pending[day] = (_pending[day] ?? const ReportDay()).plus(
      ReportDay(
        total: count,
        sites: named ? <String, int>{site: count} : const <String, int>{},
      ),
    );
    _timer ??= Timer(saveEvery, () => flush().ignore());
  }

  /// Whether counts wait to be saved.
  bool get hasPending => _pending.isNotEmpty;

  /// Counts up on [discard] and [clear]: a save that started before
  /// either must not write, or queue again, what it holds.
  int _generation = 0;
  Future<void>? _saveInFlight;

  /// Writes what was counted since the last save. Safe to call any time;
  /// when the vault is locked the counts wait for the next call.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    if (_saving) return _saveInFlight;
    final Future<void> save = _save();
    _saveInFlight = save;
    return save;
  }

  Future<void> _save() async {
    _saving = true;
    final int generation = _generation;
    final Map<String, ReportDay> adding = <String, ReportDay>{..._pending};
    _pending.clear();
    try {
      final String deviceId = await ref.read(ztDeviceIdProvider.future);
      final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
      final PrivacyReport old =
          await PrivacyReport.collection.get(store, 'report-$deviceId') ??
          PrivacyReport(deviceId: deviceId);
      // Cleared, or the account changed, while waiting: drop it.
      if (generation != _generation) return;
      await PrivacyReport.collection.save(
        ref.read(ztSyncControllerProvider.notifier),
        store,
        old.merged(
          adding,
          now: DateTime.now(),
          withSites: ref.read(browserSettingsProvider).historyDays != 0,
        ),
      );
    } on Object {
      // Not unlocked, or the store is busy: keep the counts for next time.
      if (generation == _generation) {
        for (final MapEntry<String, ReportDay> e in adding.entries) {
          _pending[e.key] = (_pending[e.key] ?? const ReportDay()).plus(
            e.value,
          );
        }
      }
    } finally {
      _saving = false;
      _saveInFlight = null;
    }
  }

  /// Drops what was counted and not saved yet. For sign-out: the counts
  /// belong to the account that left, never to the next one.
  void discard() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  /// Forgets the report on every device.
  Future<void> clear() async {
    discard();
    // A save past its last check finishes first, so the delete wins.
    await _saveInFlight;
    final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
    final SyncController sync = ref.read(ztSyncControllerProvider.notifier);
    for (final PrivacyReport r in await PrivacyReport.collection.list(store)) {
      await PrivacyReport.collection.delete(sync, r.id);
    }
  }
}

final privacyReportRecorderProvider = Provider<PrivacyReportRecorder>(
  PrivacyReportRecorder.new,
);
