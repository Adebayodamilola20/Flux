import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/providers/claude/claude_live_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Anthropic's response, with each bucket's utilization controllable.
///
/// `null` stands for the case this guards: a bucket that arrives with no
/// numeric figure in it, which the parser cannot turn into a window.
String _body({Object? fiveHour = 10, Object? sevenDay = 36}) {
  return jsonEncode({
    'five_hour': {
      'utilization': fiveHour,
      'resets_at': '2026-09-06T11:00:00.000000+00:00',
    },
    'seven_day': {
      'utilization': sevenDay,
      'resets_at': '2026-09-06T11:00:00.000000+00:00',
    },
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('claude_carry');
    Directory('${home.path}/.claude').createSync();
    File('${home.path}/.claude/.credentials.json').writeAsStringSync(
      '{"claudeAiOauth":{"accessToken":"tok","expiresAt":'
      '${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}}}',
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  ClaudeLiveUsageSource build(List<String> bodies) {
    var call = 0;
    return ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async {
        final body = bodies[call.clamp(0, bodies.length - 1)];
        call++;
        return http.Response(body, 200);
      }),
    );
  }

  group('a response that leaves a window out', () {
    test('keeps the figure rather than losing the window', () async {
      // The weekly bucket sometimes comes back with no numeric utilization.
      // The parser cannot use that, so the window was dropped and "This week"
      // simply stopped being listed — a quota does not cease to exist between
      // two polls, and the card said nothing about why it had gone.
      final source = build([_body(), _body(sevenDay: null)]);

      final (first, _) = await source.fetch();
      expect(first!.windows.map((w) => w.id), ['five_hour', 'seven_day']);

      final (second, _) = await source.fetch();

      expect(second!.windows.map((w) => w.id), ['five_hour', 'seven_day']);
      final week = second.windows.firstWhere((w) => w.id == 'seven_day');
      expect(week.percentUsed, 36);
    });

    test('and marks the carried figure as not current', () async {
      // Carried forward, not re-measured. It has to say so, or an old number
      // is presented as this poll's answer.
      final source = build([_body(), _body(sevenDay: null)]);
      await source.fetch();
      final (second, _) = await source.fetch();

      final week = second!.windows.firstWhere((w) => w.id == 'seven_day');
      final session = second.windows.firstWhere((w) => w.id == 'five_hour');

      expect(week.observedAt, isNotNull);
      // The window that did come back is current, and must not be tarred with
      // the other one's age.
      expect(session.observedAt, isNull);
    });

    test('a fresh figure replaces the carried one', () async {
      final source = build([_body(), _body(sevenDay: null), _body(sevenDay: 41)]);
      await source.fetch();
      await source.fetch();

      final (third, _) = await source.fetch();
      final week = third!.windows.firstWhere((w) => w.id == 'seven_day');

      expect(week.percentUsed, 41);
      expect(week.observedAt, isNull);
    });

    test('nothing is carried across a sign-in change', () async {
      // `reset` is what a new account and a deliberate refresh both call. A
      // window held from the previous account would be somebody else's.
      final source = build([_body(), _body(sevenDay: null)]);
      await source.fetch();
      source.reset();

      final (second, _) = await source.fetch();

      expect(second!.windows.map((w) => w.id), ['five_hour']);
    });
  });
}
