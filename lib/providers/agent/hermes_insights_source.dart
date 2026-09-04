import 'dart:io';

import '../../core/logger.dart';
import '../cli/terminal_text.dart';
import 'agent_session_store.dart';

/// Reads Hermes's own `insights` report.
///
/// **Why not a database.** Hermes keeps `state.db`, but it is not readable from
/// outside the agent, and its session directory holds request dumps rather than
/// totals. What it does offer is `hermes insights --days N`, which prints a
/// "Models Used" table — model, sessions, tokens — and `hermes status`, which
/// names the model it is currently set to. Those two are the supported way to
/// ask, so those are what is used.
///
/// **This is a rendered report, not a contract.** A layout change can make it
/// unreadable, and when that happens the result is no reading at all rather
/// than a wrong one — every figure here has to come from a line that matched.
class HermesInsightsSource implements AgentUsageReader {
  HermesInsightsSource({
    required this.executable,
    this.sessionsDirectory,
    this.authPath,
    Logger? logger,
  }) : _log = logger ?? const Logger('hermes.insights');

  /// Absolute path to the `hermes` binary, or its name if it is on the PATH.
  final String executable;

  /// Where Hermes writes as it works. Statted to notice a new session without
  /// paying for the report, which starts a Python process.
  final String? sessionsDirectory;

  /// Where Hermes keeps its sign-in. Statted for the same reason: a change of
  /// account should reach the rail without waiting for the next poll.
  final String? authPath;

  final Logger _log;

  @override
  bool get isAvailable => File(executable).existsSync();

  @override
  DateTime? get changedAt =>
      AgentSessionStore.newestOf([?sessionsDirectory, ?authPath]);

  /// The model Hermes is set to, from `hermes status`.
  ///
  /// Returned as `(model, provider)`. Null when the report did not name one —
  /// which is not an error, only a reason to fall back to the busiest model in
  /// the insights table.
  static (String, String)? parseStatus(String raw) {
    final text = TerminalText.stripAnsi(raw);
    String? model;
    String? provider;

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      // `  Model:        tencent/hy3:free`
      final match = RegExp(r'^(Model|Provider):\s+(\S.*?)\s*$').firstMatch(
        trimmed,
      );
      if (match == null) continue;
      if (match.group(1) == 'Model') {
        model ??= match.group(2);
      } else {
        provider ??= match.group(2);
      }
    }

    if (model == null) return null;
    return (model, provider ?? 'Hermes');
  }

  /// The "Models Used" table from `hermes insights`.
  ///
  /// The report prints it as `model  sessions  tokens`, right-aligned with
  /// thousands separators. Rows are only accepted when all three columns are
  /// present and the last two are numbers, so a heading, a rule, or a summary
  /// line cannot be mistaken for a model.
  static List<AgentModelUsage> parseInsights(String raw, {DateTime? at}) {
    final text = TerminalText.stripAnsi(raw);
    final lines = text.split('\n');

    final models = <AgentModelUsage>[];
    var inTable = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.contains('Models Used')) {
        inTable = true;
        continue;
      }
      if (!inTable) continue;

      // The next section heading ends the table. Every heading in the report
      // opens with a pictograph, and no data row does.
      if (models.isNotEmpty && _startsSection(trimmed)) break;

      // `hy3:free    33    919,926`
      final match = RegExp(
        r'^(\S.*?)\s{2,}([\d,]+)\s+([\d,]+)$',
      ).firstMatch(trimmed);
      if (match == null) continue;

      final name = match.group(1)!.trim();
      // Skips the column header, whose cells are words rather than numbers.
      if (name.toLowerCase() == 'model') continue;

      final sessions = int.tryParse(match.group(2)!.replaceAll(',', ''));
      final tokens = int.tryParse(match.group(3)!.replaceAll(',', ''));
      if (sessions == null || tokens == null) continue;

      models.add(AgentModelUsage(
        model: name,
        provider: 'Hermes',
        tokens: tokens,
        sessions: sessions,
        lastUsedAt: at ?? DateTime.now(),
      ));
    }

    return models;
  }

  /// True when a line opens a new section of the report.
  ///
  /// Tested by code point rather than by a character class, because the
  /// pictographs Hermes uses for its headings sit outside the Basic
  /// Multilingual Plane and a literal range in a Dart pattern would be matching
  /// surrogate halves.
  static bool _startsSection(String line) {
    if (line.isEmpty) return false;
    final rune = line.runes.first;
    return rune >= 0x1F300 && rune <= 0x1FAFF;
  }

  /// Runs both commands and combines them.
  @override
  Future<AgentUsageReading> read({
    Duration window = const Duration(days: 7),
  }) async {
    if (!isAvailable) {
      return const AgentUsageReading.unavailable(
        'Hermes is not installed on this Mac.',
      );
    }

    final insights = await _run(['insights', '--days', '${window.inDays}']);
    if (insights == null) {
      return const AgentUsageReading.unavailable(
        'Hermes’s insights report could not be read.',
      );
    }

    final models = parseInsights(insights);
    if (models.isEmpty) {
      return AgentUsageReading.unavailable(
        'Hermes has recorded no sessions in the last ${window.inDays} days.',
      );
    }

    // Which model it is *set to* is a different question from which it has
    // used most, and the first is the one the rail should be about. If status
    // names a model with no rows in the window, it is still the active one —
    // at zero, which is the honest figure for a model just switched to.
    final status = await _run(['status']);
    final named = status == null ? null : parseStatus(status);

    var active = models.first;
    if (named != null) {
      final (model, provider) = named;
      active = models.firstWhere(
        (m) => m.model == model || model.endsWith('/${m.model}'),
        orElse: () => AgentModelUsage(
          model: model,
          provider: provider,
          tokens: 0,
          sessions: 0,
          lastUsedAt: DateTime.now(),
        ),
      );
    }

    final byVolume = [...models]..sort((a, b) => b.tokens.compareTo(a.tokens));
    return AgentUsageReading(models: byVolume, active: active);
  }

  Future<String?> _run(List<String> arguments) async {
    ProcessResult result;
    try {
      result = await Process.run(executable, arguments)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      _log.warn('hermes ${arguments.first} failed: ${e.runtimeType}');
      return null;
    }
    if (result.exitCode != 0) {
      _log.warn('hermes ${arguments.first} exited ${result.exitCode}');
      return null;
    }
    return result.stdout as String;
  }
}
