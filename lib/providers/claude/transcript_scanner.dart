import 'dart:convert';
import 'dart:io';

/// A single billable model turn recorded in a local Claude Code transcript.
class TranscriptEvent {
  const TranscriptEvent({
    required this.id,
    required this.timestamp,
    required this.tokens,
    this.model,
    this.workingDirectory,
  });

  /// Transcript-assigned uuid, used to deduplicate across re-reads.
  final String id;
  final DateTime timestamp;

  /// Total tokens for the turn: input + cache creation + cache read + output.
  final int tokens;
  final String? model;

  /// The directory the session was working in, used to name the active session.
  final String? workingDirectory;
}

/// Where scanning of one transcript file left off, so the next refresh only
/// reads bytes that were appended since.
class TranscriptCursor {
  const TranscriptCursor({required this.path, required this.offset});

  final String path;

  /// Byte offset of the end of the last *complete* line consumed.
  final int offset;
}

/// Result of one scan pass.
class ScanResult {
  const ScanResult({required this.events, required this.cursors});

  final List<TranscriptEvent> events;
  final List<TranscriptCursor> cursors;
}

/// Arguments for [scanTranscripts]. Kept as plain data so the whole scan can
/// run inside `Isolate.run` without capturing anything unsendable.
class ScanRequest {
  const ScanRequest({
    required this.rootPath,
    required this.cursors,
    required this.notBefore,
  });

  /// Usually `~/.claude/projects`.
  final String rootPath;

  /// Previously recorded cursors, keyed by absolute file path.
  final Map<String, int> cursors;

  /// Files last modified before this are skipped entirely, and events older
  /// than this are discarded.
  final DateTime notBefore;
}

/// Reads Claude Code's local session transcripts and extracts token usage.
///
/// This is a pure function over the filesystem with no Flutter dependencies, so
/// it can be executed on a background isolate. It reads only the JSONL files
/// Claude Code writes for its own sessions; it never touches credentials and
/// never emits prompt or response content.
///
/// Resilient by design: a malformed line, an unreadable file, or a schema the
/// scanner does not recognise is skipped rather than failing the whole scan.
Future<ScanResult> scanTranscripts(ScanRequest request) async {
  final root = Directory(request.rootPath);
  if (!root.existsSync()) {
    return const ScanResult(events: [], cursors: []);
  }

  final events = <TranscriptEvent>[];
  final cursors = <TranscriptCursor>[];

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.jsonl')) continue;

    FileStat stat;
    try {
      stat = await entity.stat();
    } on FileSystemException {
      continue;
    }

    final previousOffset = request.cursors[entity.path] ?? 0;

    // Nothing new and nothing recent: skip without opening the file.
    if (stat.modified.isBefore(request.notBefore) &&
        previousOffset >= stat.size) {
      continue;
    }

    // A shrunk file means it was rotated or rewritten — start over.
    final startOffset = previousOffset > stat.size ? 0 : previousOffset;

    try {
      final scanned = await _scanFile(entity, startOffset, request.notBefore);
      events.addAll(scanned.events);
      cursors.add(TranscriptCursor(path: entity.path, offset: scanned.offset));
    } on FileSystemException {
      // Unreadable file: keep the old cursor so a later pass can retry.
      cursors.add(TranscriptCursor(path: entity.path, offset: startOffset));
    }
  }

  return ScanResult(events: events, cursors: cursors);
}

class _FileScan {
  const _FileScan(this.events, this.offset);
  final List<TranscriptEvent> events;
  final int offset;
}

Future<_FileScan> _scanFile(
  File file,
  int startOffset,
  DateTime notBefore,
) async {
  final events = <TranscriptEvent>[];

  final handle = await file.open();
  try {
    final length = await handle.length();
    if (startOffset >= length) return _FileScan(events, length);
    await handle.setPosition(startOffset);

    // Read the appended region in one go. On a steady-state refresh this is a
    // few kilobytes; on a cold start it is the whole file, which is why the
    // caller runs this on a background isolate.
    final bytes = await handle.read(length - startOffset);
    final text = const Utf8Decoder(allowMalformed: true).convert(bytes);

    var consumed = startOffset;
    final lines = text.split('\n');

    // The final element is either an incomplete line or an empty string after a
    // trailing newline. Either way it is not safe to consume yet.
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i];
      consumed += utf8.encode(line).length + 1;
      final event = _parseLine(line);
      if (event != null && !event.timestamp.isBefore(notBefore)) {
        events.add(event);
      }
    }
    return _FileScan(events, consumed);
  } finally {
    await handle.close();
  }
}

/// Parses one JSONL record, returning null for anything that is not an
/// assistant turn carrying token usage.
TranscriptEvent? _parseLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;

  // Cheap pre-filter so we do not pay JSON decoding for the many non-usage
  // records (user turns, snapshots, mode changes) in a transcript.
  if (!trimmed.contains('"usage"')) return null;

  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['type'] != 'assistant') return null;

  final message = decoded['message'];
  if (message is! Map<String, dynamic>) return null;
  final usage = message['usage'];
  if (usage is! Map<String, dynamic>) return null;

  final timestamp = switch (decoded['timestamp']) {
    final String s => DateTime.tryParse(s)?.toLocal(),
    _ => null,
  };
  if (timestamp == null) return null;

  final id = switch (decoded['uuid']) {
    final String s when s.isNotEmpty => s,
    _ => '${decoded['requestId']}',
  };

  final tokens = _int(usage['input_tokens']) +
      _int(usage['cache_creation_input_tokens']) +
      _int(usage['cache_read_input_tokens']) +
      _int(usage['output_tokens']);
  if (tokens <= 0) return null;

  return TranscriptEvent(
    id: id,
    timestamp: timestamp,
    tokens: tokens,
    model: message['model'] as String?,
    workingDirectory: decoded['cwd'] as String?,
  );
}

int _int(Object? value) => switch (value) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
