import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/cli/cli_quota_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A moment the relative-reset tests can anchor to.
final _now = DateTime(2026, 8, 30, 14, 0);

void main() {
  group('shape of the reading', () {
    test('labels everything it reads as a CLI panel figure', () {
      final reading = CliQuotaParser.parse(
        'Model requests   45 / 100',
        now: _now,
      );

      // Never officialApi: a rendered panel has no contract behind it.
      expect(reading.windows.single.source, UsageSource.interactiveCli);
      expect(reading.windows.single.source.isProviderReported, isTrue);
      expect(reading.windows.single.source.isAuthoritative, isFalse);
    });

    test('reads a used/limit pair', () {
      final w = CliQuotaParser.parse(
        'Model requests   45 / 100   resets in 3h',
        now: _now,
      ).windows.single;

      expect(w.label, 'Model requests');
      expect(w.consumed, 45);
      expect(w.limit, 100);
      expect(w.percentUsed, 45);
      expect(w.unit, 'requests');
    });

    test('reads a bare percentage', () {
      final w = CliQuotaParser.parse('Daily quota: 62% used', now: _now)
          .windows
          .single;

      expect(w.consumed, 62);
      expect(w.limit, 100);
      expect(w.percentUsed, 62);
    });

    test('inverts a figure expressed as remaining', () {
      final w = CliQuotaParser.parse('Credits: 30% remaining', now: _now)
          .windows
          .single;

      // The bar measures consumption, so "30% left" is 70% used.
      expect(w.percentUsed, 70);
    });

    test('picks up the unit the panel used', () {
      expect(
        CliQuotaParser.parse('Prompt credits 3 of 25', now: _now)
            .windows
            .single
            .unit,
        'credits',
      );
      expect(
        CliQuotaParser.parse('Chat messages 8/50', now: _now)
            .windows
            .single
            .unit,
        'messages',
      );
    });

    test('handles thousands separators', () {
      final w = CliQuotaParser.parse(
        'Tokens used  1,250,000 of 5,000,000',
        now: _now,
      ).windows.single;

      expect(w.consumed, 1250000);
      expect(w.limit, 5000000);
    });
  });

  group('reset times', () {
    test('resolves a relative reset', () {
      final w = CliQuotaParser.parse(
        'Model requests 45/100 resets in 3h 12m',
        now: _now,
      ).windows.single;

      expect(w.resetsAt, _now.add(const Duration(hours: 3, minutes: 12)));
    });

    test('resolves an absolute reset later today', () {
      final w = CliQuotaParser.parse(
        'Daily requests 10/50 resets at 8:39 PM',
        now: _now,
      ).windows.single;

      expect(w.resetsAt, DateTime(2026, 8, 30, 20, 39));
    });

    test('rolls an already-passed reset time to tomorrow', () {
      final w = CliQuotaParser.parse(
        'Daily requests 10/50 resets at 2:00 AM',
        now: _now,
      ).windows.single;

      expect(w.resetsAt, DateTime(2026, 8, 31, 2, 0));
    });

    test('leaves the reset unknown when the panel does not say', () {
      final w = CliQuotaParser.parse('Model requests 45/100', now: _now)
          .windows
          .single;
      expect(w.resetsAt, isNull);
    });
  });

  group('tolerance to layout changes', () {
    // The same information, laid out four different ways. A CLI update that
    // reshuffles its panel must not silently produce a rail reading 0%.
    const layouts = <String, String>{
      'aligned columns': 'Model requests        45 / 100     resets in 3h',
      'table borders':
          '│ Model requests │ 45/100 │ resets in 3h │',
      'bulleted': '  • Model requests: 45 of 100 (resets in 3h)',
      'progress bar':
          'Model requests ████████░░░░░░ 45/100 · resets in 3h',
    };

    layouts.forEach((name, line) {
      test('reads a $name layout', () {
        final w = CliQuotaParser.parse(line, now: _now).windows.single;
        expect(w.consumed, 45);
        expect(w.limit, 100);
        expect(w.label, contains('Model requests'));
        expect(w.resetsAt, _now.add(const Duration(hours: 3)));
      });
    });

    test('reads a label printed after the numbers', () {
      final w = CliQuotaParser.parse('45/100 model requests today', now: _now)
          .windows
          .single;
      expect(w.label, contains('model requests'));
      expect(w.consumed, 45);
    });
  });

  group('things that are not quotas', () {
    test('ignores prose and version strings', () {
      expect(CliQuotaParser.parse('Antigravity CLI 1.1.22').windows, isEmpty);
      expect(CliQuotaParser.parse('Gemini 3.7 Flash · high').windows, isEmpty);
      expect(CliQuotaParser.parse('/tmp').windows, isEmpty);
    });

    test('ignores upgrade prompts that quote numbers', () {
      expect(
        CliQuotaParser.parse('Upgrade for 5000 requests/month').windows,
        isEmpty,
      );
    });

    test('ignores links and key hints', () {
      expect(
        CliQuotaParser.parse('Learn more: https://example.com/limits 10/20')
            .windows,
        isEmpty,
      );
      expect(CliQuotaParser.parse('↑/↓ Navigate · enter Confirm').windows,
          isEmpty);
    });

    test('rejects a fraction where used exceeds the limit', () {
      // Far more likely to be a version or a date than a quota.
      expect(CliQuotaParser.parse('requests 2026/100').windows, isEmpty);
    });

    test('rejects an impossible percentage', () {
      expect(CliQuotaParser.parse('scaled 400% quota').windows, isEmpty);
    });
  });

  group('header details', () {
    test('reads the plan tier the CLI names', () {
      // The real header line, captured from agy.
      const header =
          'someone@example.com (Antigravity Starter Quota)';
      final reading = CliQuotaParser.parse(header, now: _now);

      expect(reading.planLabel, 'Antigravity Starter Quota');
      expect(reading.accountLabel, 'someone@example.com');
    });

    test('survives a header with no plan in it', () {
      final reading = CliQuotaParser.parse('someone@example.com', now: _now);
      expect(reading.accountLabel, 'someone@example.com');
      expect(reading.planLabel, isNull);
    });
  });

  group('a whole panel', () {
    // Representative of what a probe captures: startup noise, the header, the
    // quota rows, and the footer hints.
    const panel = '''
\x1B[>4m\x1B[=0;1u Antigravity CLI 1.1.22
  someone@example.com (Antigravity Starter Quota)
  Gemini 3.7 Flash (High)
────────────────────────────────────────────
  Usage
  Model requests       45 / 100    resets in 3h 12m
  Premium requests      2 / 20     resets in 3h 12m
  Daily credits        62% used
────────────────────────────────────────────
  esc to close · ↑/↓ Navigate
''';

    test('reads every quota row and nothing else', () {
      final reading = CliQuotaParser.parse(panel, now: _now);

      expect(reading.windows.map((w) => w.label), [
        'Model requests',
        'Premium requests',
        'Daily credits',
      ]);
      expect(reading.planLabel, 'Antigravity Starter Quota');
      expect(reading.accountLabel, 'someone@example.com');
    });

    test('gives every window a distinct id', () {
      final ids = CliQuotaParser.parse(panel, now: _now)
          .windows
          .map((w) => w.id)
          .toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('reports nothing rather than zero for an unreadable panel', () {
      // A panel that failed to draw must produce an empty reading, which the
      // provider turns into "usage unavailable" — never a 0% ring.
      final reading = CliQuotaParser.parse(
        '\x1B[2J\x1B[H⣾ Loading…\n',
        now: _now,
      );
      expect(reading.isEmpty, isTrue);
    });
  });

  group("Antigravity's /usage panel", () {
    // Captured verbatim from `agy` 1.1.22. Sectioned, with the figure drawn as
    // an unlabelled bar and then restated with the reset time on the next line
    // — the layout that a line-at-a-time reading gets wrong in three separate
    // ways, so it is worth pinning to the real bytes.
    const panel = '''
  someone@example.com (Antigravity Starter Quota)
└ Models & Quota
  Account: someone@example.com
GEMINI MODELS
  Models within this group: Gemini Flash, Gemini Pro
  Weekly Limit Remaining
    [█████████████████████████████████████████████████░] 98.98%
    99% remaining · Refreshes in 145h 16m
CLAUDE AND GPT MODELS
  Models within this group: Claude Opus, Claude Sonnet, GPT-OSS
  Weekly Limit Remaining
    [██████████████████████████████████████████████████] 100.00%
    Quota available
  │Within each group, models share a weekly limit. Quota is consumed
  │proportionally to the cost of the tokens.
  ↑/↓ Scroll · pgup/pgdown Page · esc Close
''';

    test('reads one window per model group', () {
      final reading = CliQuotaParser.parse(panel, now: _now);

      // Two groups, not four: the bar and its restatement are one quota.
      expect(reading.windows.map((w) => w.label), [
        'Gemini models',
        'Claude and GPT models',
      ]);
    });

    test('reads the panel as consumption, not as what is left', () {
      final reading = CliQuotaParser.parse(panel, now: _now);

      // "98.98% remaining" is 1% used. Reading the bar at face value would put
      // the ring at 99% and tell the user they were nearly out.
      expect(reading.windows.first.percentUsed, 1);

      // A group with its full allowance is 0% used, not 100%.
      expect(reading.windows.last.percentUsed, 0);
    });

    test('takes the reset time from the line that restates the figure', () {
      final reading = CliQuotaParser.parse(panel, now: _now);

      expect(
        reading.windows.first.resetsAt,
        _now.add(const Duration(hours: 145, minutes: 16)),
      );
    });

    test('reads the account and tier from the header', () {
      final reading = CliQuotaParser.parse(panel, now: _now);

      expect(reading.accountLabel, 'someone@example.com');
      expect(reading.planLabel, 'Antigravity Starter Quota');
    });

    test('ignores the explanatory prose and the key hints', () {
      final reading = CliQuotaParser.parse(panel, now: _now);
      expect(reading.windows, hasLength(2));
    });
  });

}
