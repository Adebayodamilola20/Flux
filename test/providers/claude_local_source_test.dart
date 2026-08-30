import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_local_source.dart';
import 'package:flutter_test/flutter_test.dart';

String line({
  required String uuid,
  required DateTime timestamp,
  int tokens = 1000,
  String cwd = '/Users/test/demo-project',
}) {
  return jsonEncode({
    'type': 'assistant',
    'uuid': uuid,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'cwd': cwd,
    'message': {
      'model': 'claude-opus-5',
      'usage': {
        'input_tokens': tokens,
        'cache_creation_input_tokens': 0,
        'cache_read_input_tokens': 0,
        'output_tokens': 0,
      },
    },
  });
}

void main() {
  late Directory home;
  late ClaudeLocalSource source;

  const settings = AppSettings(
    sessionTokenBudget: 10000,
    weeklyTokenBudget: 100000,
  );

  setUp(() async {
    home = await Directory.systemTemp.createTemp('claude_home_test');
    Directory('${home.path}/projects/-Users-test-demo-project')
        .createSync(recursive: true);
    source = ClaudeLocalSource(claudeHome: home.path);
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  Future<void> writeTurns(List<String> lines) async {
    final file = File(
      '${home.path}/projects/-Users-test-demo-project/session.jsonl',
    );
    await file.writeAsString(lines.map((l) => '$l\n').join());
  }

  group('availability', () {
    test('is unavailable without a projects directory', () async {
      final empty = await Directory.systemTemp.createTemp('claude_empty');
      addTearDown(() => empty.delete(recursive: true));
      expect(ClaudeLocalSource(claudeHome: empty.path).isAvailable, isFalse);
    });

    test('is available once transcripts exist', () {
      expect(source.isAvailable, isTrue);
    });
  });

  group('session window', () {
    test('sums turns inside the active five-hour block', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'a', timestamp: now.subtract(const Duration(minutes: 90)),
            tokens: 1500),
        line(uuid: 'b', timestamp: now.subtract(const Duration(minutes: 30)),
            tokens: 2000),
      ]);

      final usage = await source.load(settings);
      final session = usage.windows.firstWhere((w) => w.id == 'session');

      expect(session.consumed, 3500);
      expect(session.limit, 10000);
      expect(session.percentUsed, 35);
      expect(session.source, UsageSource.localTracking);
    });

    test('excludes turns from an expired block', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'old', timestamp: now.subtract(const Duration(hours: 30)),
            tokens: 9000),
        line(uuid: 'new', timestamp: now.subtract(const Duration(minutes: 10)),
            tokens: 1000),
      ]);

      final usage = await source.load(settings);
      final session = usage.windows.firstWhere((w) => w.id == 'session');

      expect(session.consumed, 1000,
          reason: 'a turn from yesterday is not part of this session block');
    });

    test('reports an empty session when the last block has expired', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'stale', timestamp: now.subtract(const Duration(hours: 12))),
      ]);

      final usage = await source.load(settings);
      final session = usage.windows.firstWhere((w) => w.id == 'session');

      expect(session.consumed, 0);
      expect(session.percentUsed, 0);
      expect(session.resetsAt, isNull,
          reason: 'there is no active block to reset');
    });

    test('anchors the reset time five hours after the block start hour',
        () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 1));
      await writeTurns([line(uuid: 'a', timestamp: start)]);

      final usage = await source.load(settings);
      final session = usage.windows.firstWhere((w) => w.id == 'session');
      final expected = DateTime(start.year, start.month, start.day, start.hour)
          .add(const Duration(hours: 5));

      expect(session.resetsAt, expected);
    });

    test('starts a new block when turns are more than five hours apart',
        () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'a', timestamp: now.subtract(const Duration(hours: 7)),
            tokens: 5000),
        line(uuid: 'b', timestamp: now.subtract(const Duration(minutes: 5)),
            tokens: 500),
      ]);

      final usage = await source.load(settings);
      final session = usage.windows.firstWhere((w) => w.id == 'session');
      expect(session.consumed, 500);
    });
  });

  group('weekly window', () {
    test('sums every turn inside the rolling seven days', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'a', timestamp: now.subtract(const Duration(days: 5)),
            tokens: 4000),
        line(uuid: 'b', timestamp: now.subtract(const Duration(days: 1)),
            tokens: 6000),
      ]);

      final usage = await source.load(settings);
      final weekly = usage.windows.firstWhere((w) => w.id == 'weekly');

      expect(weekly.consumed, 10000);
      expect(weekly.percentUsed, 10);
    });

    test('excludes turns older than seven days', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'ancient', timestamp: now.subtract(const Duration(days: 9)),
            tokens: 50000),
        line(uuid: 'recent', timestamp: now.subtract(const Duration(hours: 2)),
            tokens: 1000),
      ]);

      final usage = await source.load(settings);
      final weekly = usage.windows.firstWhere((w) => w.id == 'weekly');
      expect(weekly.consumed, 1000);
    });

    test('resets when the oldest counted turn ages out', () async {
      final now = DateTime.now();
      final oldest = now.subtract(const Duration(days: 3));
      await writeTurns([line(uuid: 'a', timestamp: oldest)]);

      final usage = await source.load(settings);
      final weekly = usage.windows.firstWhere((w) => w.id == 'weekly');

      expect(weekly.resetsAt, isNotNull);
      expect(
        weekly.resetsAt!.difference(oldest).inDays,
        7,
      );
    });
  });

  group('incremental loading', () {
    test('does not double-count turns across repeated loads', () async {
      final now = DateTime.now();
      await writeTurns([
        line(uuid: 'a', timestamp: now.subtract(const Duration(minutes: 10)),
            tokens: 1000),
      ]);

      final first = await source.load(settings);
      final second = await source.load(settings);

      expect(
        second.windows.firstWhere((w) => w.id == 'session').consumed,
        first.windows.firstWhere((w) => w.id == 'session').consumed,
      );
    });

    test('picks up turns appended between loads', () async {
      final now = DateTime.now();
      final file = File(
        '${home.path}/projects/-Users-test-demo-project/session.jsonl',
      );
      await file.writeAsString(
        '${line(uuid: 'a', timestamp: now, tokens: 1000)}\n',
      );
      await source.load(settings);

      await file.writeAsString(
        '${line(uuid: 'b', timestamp: now, tokens: 500)}\n',
        mode: FileMode.append,
      );
      final second = await source.load(settings);

      expect(
        second.windows.firstWhere((w) => w.id == 'session').consumed,
        1500,
      );
    });
  });

  test('reports the most recent turn for the active session label', () async {
    final now = DateTime.now();
    await writeTurns([
      line(uuid: 'a', timestamp: now.subtract(const Duration(minutes: 20))),
      line(uuid: 'b', timestamp: now.subtract(const Duration(minutes: 2))),
    ]);

    final usage = await source.load(settings);
    expect(usage.latestEvent?.id, 'b');
    expect(usage.latestEvent?.workingDirectory, '/Users/test/demo-project');
  });

  test('produces zeroed windows rather than failing on an empty directory',
      () async {
    final usage = await source.load(settings);
    expect(usage.windows, hasLength(2));
    expect(usage.windows.every((w) => w.consumed == 0), isTrue);
    expect(usage.latestEvent, isNull);
  });
}
