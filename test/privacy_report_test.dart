import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_browser/data/browser_data.dart';
import 'package:zerotrust_browser/data/models.dart';
import 'package:zerotrust_browser/browser/privacy_report.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 10, 15);

  test('counts add up per day and site', () {
    final PrivacyReport r = const PrivacyReport(deviceId: 'd1')
        .merged(<String, ReportDay>{
          '2026-11-10': const ReportDay(
            total: 5,
            sites: <String, int>{'a.example': 3, 'b.example': 2},
          ),
        }, now: now)
        .merged(<String, ReportDay>{
          '2026-11-10': const ReportDay(
            total: 4,
            sites: <String, int>{'a.example': 1},
          ),
        }, now: now);
    expect(r.id, 'report-d1');
    expect(r.days['2026-11-10']!.total, 9);
    expect(r.days['2026-11-10']!.sites, <String, int>{
      'a.example': 4,
      'b.example': 2,
    });
    final PrivacyReport back = PrivacyReport.fromJson(r.id, r.toJson(), now);
    expect(back.deviceId, 'd1');
    expect(back.days['2026-11-10']!.sites['a.example'], 4);
  });

  test('old days drop out and site names go when history is off', () {
    final PrivacyReport r = PrivacyReport(
      deviceId: 'd1',
      days: <String, ReportDay>{
        '2026-10-13': const ReportDay(total: 7),
        '2026-10-14': const ReportDay(
          total: 2,
          sites: <String, int>{'a.example': 2},
        ),
      },
    );
    final PrivacyReport kept = r.merged(const <String, ReportDay>{}, now: now);
    expect(kept.days.keys, <String>['2026-10-14']);
    final PrivacyReport bare = r.merged(
      const <String, ReportDay>{},
      now: now,
      withSites: false,
    );
    expect(bare.days['2026-10-14']!.total, 2);
    expect(bare.days['2026-10-14']!.sites, isEmpty);
  });

  test('only the busiest sites of a day are kept', () {
    final PrivacyReport r = const PrivacyReport(deviceId: 'd').merged(
      <String, ReportDay>{
        '2026-11-10': ReportDay(
          total: 1000,
          sites: <String, int>{
            for (int i = 0; i < 150; i++) 's$i.example': i + 1,
          },
        ),
      },
      now: now,
    );
    final Map<String, int> sites = r.days['2026-11-10']!.sites;
    expect(sites, hasLength(PrivacyReport.sitesPerDay));
    expect(sites.containsKey('s149.example'), isTrue);
    expect(sites.containsKey('s0.example'), isFalse);
  });

  test('the summary adds all devices: week, month, top sites', () {
    final ReportSummary s = ReportSummary.of(<PrivacyReport>[
      const PrivacyReport(
        deviceId: 'phone',
        days: <String, ReportDay>{
          '2026-11-10': ReportDay(
            total: 10,
            sites: <String, int>{'a.example': 6, 'b.example': 4},
          ),
          '2026-11-04': ReportDay(
            total: 3,
            sites: <String, int>{'b.example': 3},
          ),
          '2026-11-03': ReportDay(total: 100),
        },
      ),
      const PrivacyReport(
        deviceId: 'tablet',
        days: <String, ReportDay>{
          '2026-11-10': ReportDay(
            total: 2,
            sites: <String, int>{'b.example': 2},
          ),
        },
      ),
    ], now: now);
    expect(s.lastDays, <int>[3, 0, 0, 0, 0, 0, 12]);
    expect(s.week, 15);
    expect(s.month, 115);
    expect(s.topSites.first.key, 'b.example');
    expect(s.topSites.first.value, 9);
    expect(s.topSites.last.key, 'a.example');
  });

  test('days are named in local time, across a month end', () {
    expect(reportDay(DateTime(2026, 3, 1 - 1)), '2026-02-28');
  });

  group('recorder', () {
    late int asked;
    late Completer<String> deviceId;

    ProviderContainer container() {
      asked = 0;
      deviceId = Completer<String>();
      final ProviderContainer c = ProviderContainer(
        overrides: [
          browserSettingsProvider.overrideWithValue(const BrowserSettings()),
          ztDeviceIdProvider.overrideWith((ref) {
            asked++;
            return deviceId.future;
          }),
          // No vault in this test: saving fails as it does when locked.
          ztLocalStoreProvider.overrideWith(
            (ref) => throw StateError('locked'),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('counts wait while locked and are tried again', () async {
      final ProviderContainer c = container();
      final PrivacyReportRecorder r = c.read(privacyReportRecorderProvider);
      r.add('a.example', 2, now: now);
      deviceId.complete('d1');
      await r.flush();
      expect(asked, 1);
      // Still held for the next try.
      expect(r.hasPending, isTrue);
      r.discard();
    });

    test('nothing is kept after sign-out', () async {
      final ProviderContainer c = container();
      final PrivacyReportRecorder r = c.read(privacyReportRecorderProvider);
      r.add('a.example', 2, now: now);
      r.discard();
      await r.flush();
      expect(asked, 0);
    });

    test('a save under way when the report is cleared is dropped', () async {
      final ProviderContainer c = container();
      final PrivacyReportRecorder r = c.read(privacyReportRecorderProvider);
      r.add('a.example', 2, now: now);
      final Future<void> saving = r.flush();
      // Cleared (here: discarded) before the save got to the store.
      r.discard();
      deviceId.complete('d1');
      await saving;
      // The failed save did not put its counts back.
      expect(r.hasPending, isFalse);
    });
  });
}
