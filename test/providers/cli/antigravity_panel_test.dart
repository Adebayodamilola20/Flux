import 'package:ai_usage_monitor/providers/cli/cli_quota_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The panel `agy` actually printed, transcribed from a screenshot rather than
/// imagined. The bar glyphs and box rules are what the CLI draws.
const String _panel = '''
 └ Models & Quota

   Account: someone@example.com

GEMINI MODELS
  Models within this group: Gemini Flash, Gemini Pro

    Weekly Limit Remaining
      [██████████████░░░░░░░░░░░░░░] 66.40%
      66% remaining · Refreshes in 56h 56m

CLAUDE AND GPT MODELS
  Models within this group: Claude Opus, Claude Sonnet, GPT-OSS

    Weekly Limit Remaining
      [░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 100.00%
      100% remaining · Refreshes in 56h 56m
''';

void main() {
  group('the Antigravity panel', () {
    test('reports what is used, from a CLI that reports what is left', () {
      // The CLI prints "66.40%" under a heading that says *Remaining*. Read at
      // face value that is a rail showing 66% of a quota spent when 66% of it
      // is in fact still there — the number and its meaning are inverted.
      final reading = CliQuotaParser.parse(_panel);
      final gemini = reading.windows.first;

      expect(gemini.percentUsed, 34);
      expect(gemini.limit, 100);
    });

    test('says which period the limit is over', () {
      // The group heading names what is limited; the row heading above it
      // names the period. Keeping only the group left a weekly allowance on
      // the rail as an unqualified figure, indistinguishable from a
      // per-session one — which is exactly what was noticed against the CLI.
      final reading = CliQuotaParser.parse(_panel);

      expect(reading.windows.first.label, contains('Gemini'));
      expect(reading.windows.first.label, contains('weekly'));
    });

    test('keeps the two model groups apart', () {
      final reading = CliQuotaParser.parse(_panel);

      expect(reading.windows, hasLength(2));
      expect(reading.windows[1].label, contains('Claude'));
      // Nothing spent in that group: 100% remaining is 0% used.
      expect(reading.windows[1].percentUsed, 0);
    });

    test('a heading with no period leaves the label alone', () {
      // The qualifier is only added where the CLI states one. Inventing
      // "weekly" for a panel that never said it would be a claim about
      // somebody else's quota.
      final reading = CliQuotaParser.parse('''
GEMINI MODELS

    Limit Remaining
      [██████░░░░] 60.00%
''');

      expect(reading.windows.single.label, isNot(contains('weekly')));
      expect(reading.windows.single.percentUsed, 40);
    });
  });
}
