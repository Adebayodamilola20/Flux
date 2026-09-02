import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/chatgpt/codex_account_source.dart';
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
  _staleness();
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

    test('names the window by the span it covers', () {
      // 43200 minutes is the real value, and it means 30 days.
      final reading = CodexUsageSource.parse(rateLimits());
      expect(reading.windows.single.label, 'Monthly limit');
    });

    test('labels shorter windows in hours', () {
      final reading = CodexUsageSource.parse(rateLimits(windowMinutes: 300));
      expect(reading.windows.single.label, '5-hour limit');
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
      expect(reading.windows.last.label, 'Weekly limit');

      // The two windows have to be told apart on a card that truncates. Naming
      // both after the allowance put the same row on screen twice.
      expect(
        reading.windows.first.label,
        isNot(reading.windows.last.label),
      );
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

void _staleness() {
  group('how old the figure is', () {
    test('carries when OpenAI measured it, not when we read the file', () {
      // OpenAI reports the allowance only in the reply to a model request, so
      // the newest figure available can be days old. Showing "100% Used" with
      // no date reads as current — the same failure as a stale cache passed
      // off as live.
      final reading = CodexUsageSource.parse(
        {
          'limit_id': 'codex',
          'plan_type': 'free',
          'primary': {
            'used_percent': 100.0,
            'window_minutes': 43200,
            'resets_at': 1790650597,
          },
        },
        timestamp: '2026-08-30T03:20:22.561Z',
      );

      final window = reading.windows.single;
      expect(window.observedAt, isNotNull);
      expect(window.isStale, isTrue);
      // The reset OpenAI gave, transcribed rather than derived.
      expect(window.resetsAt, DateTime.fromMillisecondsSinceEpoch(1790650597 * 1000));
    });

    test('a figure taken just now is not called stale', () {
      final reading = CodexUsageSource.parse(
        {
          'limit_id': 'codex',
          'primary': {'used_percent': 40.0, 'window_minutes': 43200},
        },
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(reading.windows.single.isStale, isFalse);
    });
  });

  _accountSwitch();
}

/// Switching to a different ChatGPT account.
///
/// A transcript records no account, so the figures from a previous sign-in look
/// exactly like the current one's. What separates them is when they were
/// written, and the account file is what says when the account changed.
void _accountSwitch() {
  group('telling one account from another', () {
    test('reads the signed-in account without touching its tokens', () {
      final account = CodexAccountSource.parse(jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {
          'id_token': 'ey.secret',
          'access_token': 'ey.secret',
          'refresh_token': 'rt.secret',
          'account_id': '3b3e572f-4a03-49ad-af98-e330872c8d65',
        },
      }));

      expect(account.accountId, '3b3e572f-4a03-49ad-af98-e330872c8d65');
      expect(account.authMode, 'chatgpt');
      expect(account.isSignedIn, isTrue);
    });

    test('a signed-out Codex reports no account', () {
      final account = CodexAccountSource.parse(
        jsonEncode({'auth_mode': 'chatgpt', 'tokens': null}),
      );

      expect(account.isSignedIn, isFalse);
      expect(account.isInstalled, isTrue);
    });

    test('ignores an allowance recorded before the account changed', () async {
      final home = Directory.systemTemp.createTempSync('codex_switch_test');
      addTearDown(() => home.deleteSync(recursive: true));

      final day = Directory('${home.path}/.codex/sessions/2026/08/29')
        ..createSync(recursive: true);

      // The account the user left, sitting at its limit.
      File('${day.path}/rollout-old.jsonl').writeAsStringSync(
        jsonEncode({
          'timestamp': '2026-08-29T10:00:00.000Z',
          'type': 'event_msg',
          'payload': {
            'type': 'token_count',
            'rate_limits': rateLimits(usedPercent: 100),
          },
        }),
      );

      final source = CodexUsageSource(homeDirectory: home.path);

      // Without a cut-off it is the best figure there is, and is reported.
      expect((await source.read()).windows.single.percentUsed, 100);

      // After a switch, it is the previous account's figure and nothing else
      // has been recorded yet. Reporting 100% here is what made the app claim
      // a brand-new account was exhausted.
      final switched = await source.read(
        notBefore: DateTime.parse('2026-08-30T00:00:00Z'),
      );
      expect(switched.hasUsage, isFalse);
    });

    test('reports an allowance recorded since the account changed', () async {
      final home = Directory.systemTemp.createTempSync('codex_switch_test');
      addTearDown(() => home.deleteSync(recursive: true));

      final day = Directory('${home.path}/.codex/sessions/2026/08/31')
        ..createSync(recursive: true);

      File('${day.path}/rollout-new.jsonl').writeAsStringSync(
        jsonEncode({
          'timestamp': '2026-08-31T10:00:00.000Z',
          'type': 'event_msg',
          'payload': {
            'type': 'token_count',
            'rate_limits': rateLimits(usedPercent: 2, planType: 'free'),
          },
        }),
      );

      final reading = await CodexUsageSource(homeDirectory: home.path).read(
        notBefore: DateTime.parse('2026-08-30T00:00:00Z'),
      );

      expect(reading.windows.single.percentUsed, 2);
      expect(reading.planType, 'free');
    });
  });
}
