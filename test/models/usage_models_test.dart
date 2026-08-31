import 'package:ai_usage_monitor/models/active_session.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_data.dart';
import 'package:ai_usage_monitor/models/usage_snapshot.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/models/usage_window.dart';
import 'package:flutter_test/flutter_test.dart';

UsageWindow window({
  String id = 'session',
  num consumed = 50,
  num? limit = 100,
  UsageSource source = UsageSource.localTracking,
  DateTime? resetsAt,
}) {
  return UsageWindow(
    id: id,
    label: 'Current session',
    consumed: consumed,
    limit: limit,
    source: source,
    resetsAt: resetsAt,
  );
}

void main() {
  group('UsageWindow', () {
    test('computes fraction and whole percent', () {
      final w = window(consumed: 52, limit: 100);
      expect(w.fractionUsed, closeTo(0.52, 1e-9));
      expect(w.percentUsed, 52);
    });

    test('rounds percent to nearest whole number', () {
      expect(window(consumed: 526, limit: 1000).percentUsed, 53);
      expect(window(consumed: 524, limit: 1000).percentUsed, 52);
    });

    test('reports null rather than guessing when no limit is known', () {
      final w = window(limit: null);
      expect(w.fractionUsed, isNull);
      expect(w.percentUsed, isNull);
      expect(w.isNearLimit, isFalse);
    });

    test('treats a zero or negative limit as unknown', () {
      expect(window(limit: 0).fractionUsed, isNull);
      expect(window(limit: -5).fractionUsed, isNull);
    });

    test('clamps over-budget usage to a full bar', () {
      final w = window(consumed: 250, limit: 100);
      expect(w.fractionUsed, 1.0);
      expect(w.percentUsed, 100);
      expect(w.isExhausted, isTrue);
    });

    test('flags the near-limit threshold at 80 percent', () {
      expect(window(consumed: 79).isNearLimit, isFalse);
      expect(window(consumed: 80).isNearLimit, isTrue);
    });

    test('round-trips through JSON', () {
      final resetsAt = DateTime(2026, 3, 4, 17, 30);
      final original = window(consumed: 1234, limit: 9999, resetsAt: resetsAt);
      final restored = UsageWindow.fromJson(original.toJson());

      expect(restored, original);
      expect(restored.resetsAt, resetsAt);
      expect(restored.source, UsageSource.localTracking);
    });

    test('falls back to an unavailable source for unknown JSON values', () {
      final restored = UsageWindow.fromJson({
        'id': 'x',
        'label': 'X',
        'consumed': 5,
        'source': 'something_new',
      });
      expect(restored.source, UsageSource.unavailable);
      expect(restored.resetsAt, isNull);
    });
  });

  group('UsageData', () {
    UsageData data(List<UsageWindow> windows) => UsageData(
          providerId: 'claude',
          providerName: 'Claude',
          windows: windows,
          connection: ConnectionStatus.connected,
          fetchedAt: DateTime(2026, 1, 1),
        );

    test('drives the menu bar from the first window', () {
      final d = data([
        window(id: 'session', consumed: 40),
        window(id: 'weekly', consumed: 90),
      ]);
      expect(d.primaryWindow?.id, 'session');
      expect(d.primaryPercent, 40);
    });

    test('reports provider-reported only when every window is', () {
      final d = data([
        window(source: UsageSource.officialApi),
        window(id: 'weekly', source: UsageSource.officialApi),
      ]);
      expect(d.source, UsageSource.officialApi);
    });

    test('degrades to local tracking when sources are mixed', () {
      final d = data([
        window(source: UsageSource.officialApi),
        window(id: 'weekly', source: UsageSource.localTracking),
      ]);
      expect(d.source, UsageSource.localTracking,
          reason: 'a mixed snapshot must not be over-claimed as authoritative');
    });

    test('reports unavailable with no windows', () {
      expect(data([]).source, UsageSource.unavailable);
      expect(data([]).primaryPercent, isNull);
      expect(data([]).hasUsage, isFalse);
    });

    test('looks windows up by id', () {
      final d = data([window(id: 'session'), window(id: 'weekly')]);
      expect(d.windowById('weekly')?.id, 'weekly');
      expect(d.windowById('missing'), isNull);
    });

    test('surfaces the first session as the active one', () {
      final d = data([window()]).copyWith(
        sessions: const [ActiveSession(title: 'demo')],
      );
      expect(d.activeSession?.title, 'demo');
      expect(d.copyWith(sessions: const []).activeSession, isNull);
    });
  });

  group('ActiveSession', () {
    test('prefixes the host when one is known', () {
      const s = ActiveSession(title: 'my-app', host: 'Terminal');
      expect(s.subtitle('my-app'), 'Terminal · my-app');
    });

    test('falls back to the bare label without a host', () {
      const s = ActiveSession(title: 'my-app');
      expect(s.subtitle('my-app'), 'my-app');
    });
  });

  group('UsageSnapshot', () {
    test('creates one snapshot per window', () {
      final d = UsageData(
        providerId: 'claude',
        providerName: 'Claude',
        windows: [window(id: 'session'), window(id: 'weekly')],
        connection: ConnectionStatus.connected,
        fetchedAt: DateTime(2026, 5, 5),
      );

      final snapshots = UsageSnapshot.fromUsage(d);
      expect(snapshots, hasLength(2));
      expect(snapshots.map((s) => s.windowId), ['session', 'weekly']);
      expect(snapshots.first.percent, 50);
    });

    test('round-trips through JSON', () {
      final snapshot = UsageSnapshot(
        takenAt: DateTime(2026, 2, 2, 10),
        providerId: 'claude',
        windowId: 'session',
        consumed: 10,
        limit: 100,
        percent: 10,
        source: UsageSource.officialApi,
      );
      final restored = UsageSnapshot.fromJson(snapshot.toJson())!;
      expect(restored.takenAt, snapshot.takenAt);
      expect(restored.percent, 10);
      expect(restored.source, UsageSource.officialApi);
    });

    test('rejects malformed records instead of throwing', () {
      expect(UsageSnapshot.fromJson({'providerId': 'claude'}), isNull);
      expect(UsageSnapshot.fromJson({'takenAt': 'not-a-date'}), isNull);
    });
  });
}
