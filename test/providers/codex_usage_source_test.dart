import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/chatgpt/codex_usage_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `rate_limits` block Codex actually records, as observed in a real
/// session history.
Map<String, dynamic> rateLimits({
  String limitId = 'codex',
  String? planType = 'plus',
  num? usedPercent = 63,
  num windowMinutes = 43200,
  int? resetsAt,
  Map<String, dynamic>? secondary,
}) {
  return {
    'limit_id': limitId,
    'limit_name': null,
    'primary': usedPercent == null
        ? null
        : {
            'used_percent': usedPercent,
            'window_minutes': windowMinutes,
            if (resetsAt != null) 'resets_at': resetsAt,
          },
    'secondary': secondary,
    'plan_type': planType,
  };
}

void main() {
  group('what the number means', () {
    test('reads the Codex plan allowance as a percentage', () {
      final reading = CodexUsageSource.parse(rateLimits());
      final window = reading.windows.single;

      expect(window.percentUsed, 63);
      expect(window.limit, 100);
      expect(window.unit, '%');
      // OpenAI computed this for the account.
      expect(window.source, UsageSource.officialApi);
    });

    test('names the window in days rather than minutes', () {
      // 43200 minutes is the real value, and it means 30 days.
      final reading = CodexUsageSource.parse(rateLimits());
      expect(reading.windows.single.label, 'Codex allowance (30 days)');
    });

    test('labels shorter windows in hours', () {
      final reading = CodexUsageSource.parse(rateLimits(windowMinutes: 300));
      expect(reading.windows.single.label, contains('5 hours'));
    });

    test('reports the plan the account is on', () {
      expect(
        CodexUsageSource.planLabel(
          CodexUsageSource.parse(rateLimits(planType: 'plus')).planType,
        ),
        'ChatGPT Plus',
      );
      expect(
        CodexUsageSource.planLabel(
          CodexUsageSource.parse(rateLimits(planType: 'free')).planType,
        ),
        'ChatGPT Free',
      );
    });

    test('resolves the reset time from a unix timestamp', () {
      final reading = CodexUsageSource.parse(
        rateLimits(resetsAt: 1790650597),
      );
      expect(reading.windows.single.resetsAt, isNotNull);
    });

    test('records when Codex observed it, not when we read it', () {
      final reading = CodexUsageSource.parse(
        rateLimits(),
        timestamp: '2026-08-30T03:20:22.561Z',
      );

      // This is a cache written by Codex, so the age has to be showable.
      expect(reading.observedAt, isNotNull);
      expect(reading.observedAt!.year, 2026);
    });

    test('includes a secondary window when there is one', () {
      final reading = CodexUsageSource.parse(
        rateLimits(
          secondary: {'used_percent': 12, 'window_minutes': 10080},
        ),
      );

      expect(reading.windows, hasLength(2));
      expect(reading.windows.last.label, contains('7 days'));
    });
  });

  group('what it must not be confused with', () {
    test('ignores buckets that are not the Codex allowance', () {
      // A `premium` bucket also appears. On the accounts observed it carried
      // no figures, and it is a different allowance regardless.
      final reading = CodexUsageSource.parse(
        rateLimits(limitId: 'premium', usedPercent: 100),
      );

      // parse() itself is bucket-agnostic; the filtering happens on read, so
      // what this pins is that the id travels with the data.
      expect(reading.windows, isNotEmpty);
      expect(CodexUsageSource.codexLimitId, 'codex');
    });

    test('reports nothing rather than zero when the bucket is empty', () {
      // The `premium` bucket on a free plan looks exactly like this. Reporting
      // it as 0% used would invent a figure.
      final reading = CodexUsageSource.parse(
        rateLimits(usedPercent: null, planType: 'free'),
      );

      expect(reading.hasUsage, isFalse);
      expect(reading.windows, isEmpty);
    });

    test('survives a block with no plan or windows at all', () {
      final reading = CodexUsageSource.parse({
        'limit_id': 'premium',
        'primary': null,
        'secondary': null,
        'plan_type': 'free',
      });

      expect(reading.hasUsage, isFalse);
      expect(reading.planType, 'free');
    });
  });
}
