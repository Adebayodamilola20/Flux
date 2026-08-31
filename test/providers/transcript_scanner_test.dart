import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/providers/claude/transcript_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds one assistant transcript record in the shape Claude Code writes.
String assistantLine({
  required String uuid,
  required DateTime timestamp,
  int input = 10,
  int cacheCreation = 20,
  int cacheRead = 30,
  int output = 40,
  String cwd = '/Users/test/project',
  String model = 'claude-opus-5',
}) {
  return jsonEncode({
    'type': 'assistant',
    'uuid': uuid,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'cwd': cwd,
    'message': {
      'model': model,
      'usage': {
        'input_tokens': input,
        'cache_creation_input_tokens': cacheCreation,
        'cache_read_input_tokens': cacheRead,
        'output_tokens': output,
      },
    },
  });
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('transcript_scan_test');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<File> writeTranscript(String name, List<String> lines) async {
    final dir = Directory('${root.path}/-Users-test-project')
      ..createSync(recursive: true);
    final file = File('${dir.path}/$name');
    await file.writeAsString(lines.map((l) => '$l\n').join());
    return file;
  }

  ScanRequest request({Map<String, int> cursors = const {}, DateTime? since}) {
    return ScanRequest(
      rootPath: root.path,
      cursors: cursors,
      notBefore: since ?? DateTime.now().subtract(const Duration(days: 7)),
    );
  }

  group('scanTranscripts', () {
    test('returns nothing when the directory does not exist', () async {
      final result = await scanTranscripts(ScanRequest(
        rootPath: '${root.path}/missing',
        cursors: const {},
        notBefore: DateTime(2020),
      ));
      expect(result.events, isEmpty);
      expect(result.cursors, isEmpty);
    });

    test('counts work tokens and keeps cache reads apart', () async {
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      await writeTranscript('a.jsonl', [
        assistantLine(uuid: 'a', timestamp: at),
      ]);

      final result = await scanTranscripts(request());
      expect(result.events, hasLength(1));

      // input + cache creation + output. Cache reads are excluded, because
      // replaying a large cached context registers tens of millions of them
      // and would swamp any figure they were folded into.
      expect(result.events.single.tokens, 70); // 10 + 20 + 40
      expect(result.events.single.cacheReadTokens, 30);
      expect(result.events.single.model, 'claude-opus-5');
      expect(result.events.single.workingDirectory, '/Users/test/project');
    });

    test('skips records that are not assistant turns with usage', () async {
      final at = DateTime.now();
      await writeTranscript('a.jsonl', [
        jsonEncode({'type': 'user', 'timestamp': at.toIso8601String()}),
        jsonEncode({'type': 'file-history-snapshot'}),
        jsonEncode({
          'type': 'assistant',
          'uuid': 'no-usage',
          'timestamp': at.toIso8601String(),
          'message': {'model': 'x'},
        }),
        assistantLine(uuid: 'real', timestamp: at),
      ]);

      final result = await scanTranscripts(request());
      expect(result.events.map((e) => e.id), ['real']);
    });

    test('survives malformed lines without losing the rest of the file',
        () async {
      final at = DateTime.now();
      await writeTranscript('a.jsonl', [
        '{"usage": not json at all',
        '',
        '   ',
        'plain text with usage in it',
        assistantLine(uuid: 'good', timestamp: at),
      ]);

      final result = await scanTranscripts(request());
      expect(result.events.map((e) => e.id), ['good']);
    });

    test('discards turns older than the retention window', () async {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await writeTranscript('a.jsonl', [
        assistantLine(
          uuid: 'old',
          timestamp: cutoff.subtract(const Duration(days: 1)),
        ),
        assistantLine(uuid: 'new', timestamp: DateTime.now()),
      ]);

      final result = await scanTranscripts(request(since: cutoff));
      expect(result.events.map((e) => e.id), ['new']);
    });

    test('resumes from a cursor and reads only appended bytes', () async {
      final file = await writeTranscript('a.jsonl', [
        assistantLine(uuid: 'first', timestamp: DateTime.now()),
      ]);

      final first = await scanTranscripts(request());
      expect(first.events.map((e) => e.id), ['first']);
      final cursor = first.cursors.single;
      expect(cursor.offset, file.lengthSync());

      await file.writeAsString(
        '${assistantLine(uuid: 'second', timestamp: DateTime.now())}\n',
        mode: FileMode.append,
      );

      final second = await scanTranscripts(
        request(cursors: {cursor.path: cursor.offset}),
      );
      expect(
        second.events.map((e) => e.id),
        ['second'],
        reason: 'already-consumed turns must not be re-emitted',
      );
    });

    test('does not consume a partially written trailing line', () async {
      final dir = Directory('${root.path}/-Users-test-project')
        ..createSync(recursive: true);
      final file = File('${dir.path}/a.jsonl');
      final complete = assistantLine(uuid: 'complete', timestamp: DateTime.now());
      // Simulate Claude Code mid-write: a complete line plus a partial one.
      await file.writeAsString('$complete\n{"type":"assistant","usage');

      final result = await scanTranscripts(request());
      expect(result.events.map((e) => e.id), ['complete']);
      expect(
        result.cursors.single.offset,
        utf8.encode(complete).length + 1,
        reason: 'the cursor must stop at the last complete newline',
      );

      // Once the partial line is finished, a resumed scan picks it up.
      final finished = assistantLine(uuid: 'finished', timestamp: DateTime.now());
      await file.writeAsString('$complete\n$finished\n');

      final resumed = await scanTranscripts(
        request(cursors: {file.path: result.cursors.single.offset}),
      );
      expect(resumed.events.map((e) => e.id), ['finished']);
    });

    test('restarts from zero when a file shrinks', () async {
      final file = await writeTranscript('a.jsonl', [
        assistantLine(uuid: 'one', timestamp: DateTime.now()),
        assistantLine(uuid: 'two', timestamp: DateTime.now()),
      ]);
      final stale = file.lengthSync();

      await file.writeAsString(
        '${assistantLine(uuid: 'rewritten', timestamp: DateTime.now())}\n',
      );

      final result = await scanTranscripts(
        request(cursors: {file.path: stale}),
      );
      expect(result.events.map((e) => e.id), ['rewritten']);
    });

    test('walks nested project directories', () async {
      final nested = Directory('${root.path}/-a/-b')..createSync(recursive: true);
      await File('${nested.path}/deep.jsonl').writeAsString(
        '${assistantLine(uuid: 'deep', timestamp: DateTime.now())}\n',
      );

      final result = await scanTranscripts(request());
      expect(result.events.map((e) => e.id), contains('deep'));
    });

    test('ignores files that are not transcripts', () async {
      final dir = Directory('${root.path}/-Users-test-project')
        ..createSync(recursive: true);
      await File('${dir.path}/notes.txt').writeAsString('usage');

      final result = await scanTranscripts(request());
      expect(result.events, isEmpty);
      expect(result.cursors, isEmpty);
    });
  });
}
