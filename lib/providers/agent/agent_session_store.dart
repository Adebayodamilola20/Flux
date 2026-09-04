import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';

/// One model, and what it has been charged for in the window asked about.
class AgentModelUsage {
  const AgentModelUsage({
    required this.model,
    required this.provider,
    required this.tokens,
    required this.sessions,
    required this.lastUsedAt,
    this.contextTokens,
    this.contextLimit,
  });

  const AgentModelUsage.context({
    required this.model,
    required this.provider,
    required this.contextTokens,
    required this.contextLimit,
    required this.lastUsedAt,
  })  : tokens = 0,
        sessions = 0;

  /// The model's own id, e.g. `z-ai/glm-5.2`.
  final String model;

  /// Who serves it, e.g. `nvidia`. Two providers can serve the same model on
  /// different allowances, so the pair is the identity, not the model alone.
  final String provider;

  final int tokens;
  final int sessions;
  final DateTime lastUsedAt;

  /// Tokens in the live conversation, as the tool itself counts them.
  ///
  /// This is the number OpenCode and Kilo Code put on screen as "Context", and
  /// it is what a user checking whether they are about to run out is actually
  /// looking at. It is the running total of the most recent assistant turn —
  /// not a sum over the session, which keeps climbing as turns are re-sent and
  /// would pass the limit while the conversation was nowhere near it.
  final int? contextTokens;

  /// The model's published context window.
  ///
  /// A real limit from the tool's own model catalogue, so the percentage
  /// against it is a fact rather than a budget anyone invented.
  final int? contextLimit;

  /// What the rail says when this model is the one in use.
  ///
  /// The bare model id, without the serving provider: the ring already belongs
  /// to OpenCode or Kilo Code, and repeating that in the label spends the
  /// width on something the user can see.
  String get label => model;

  @override
  String toString() => 'AgentModelUsage($provider/$model, $tokens tokens)';
}

/// What an agent's session store had to say.
class AgentUsageReading {
  const AgentUsageReading({
    required this.models,
    this.active,
    this.unavailableReason,
  });

  const AgentUsageReading.unavailable(String this.unavailableReason)
      : models = const [],
        active = null;

  /// Every model used in the window, busiest first.
  final List<AgentModelUsage> models;

  /// The model the agent is on now — the one the most recent session used.
  ///
  /// This is what makes a switch visible. When the user runs out on one model
  /// and moves to another, the next session carries the new model, this
  /// changes, and the rail starts reporting that model's own total instead of
  /// continuing to show the one they left.
  final AgentModelUsage? active;

  final String? unavailableReason;

  bool get hasUsage => active != null;
}

/// Somewhere an agent's own usage record can be read from.
///
/// Two shapes satisfy this: a session database ([AgentSessionStore]) and a
/// rendered report ([HermesInsightsSource]). The provider above them does not
/// care which, because the question — what has this agent spent, and on which
/// model — is the same either way.
abstract class AgentUsageReader {
  /// True when this agent has anything to read on this Mac.
  bool get isAvailable;

  /// When the record last changed, for noticing a new session without polling
  /// the whole reading. Null when there is nothing cheap to check.
  DateTime? get changedAt;

  Future<AgentUsageReading> read({Duration window});
}

/// Reads the session record OpenCode and Kilo Code keep on this Mac.
///
/// **Why the database and not the CLI.** Both ship a `stats` command, but it
/// renders a box-drawn table meant for a person, and reading a figure the user
/// depends on out of terminal art means a layout change silently becomes a
/// wrong number. The same tools write every session to SQLite first — model,
/// provider, token counts, timestamps, as columns — so that is what is read.
///
/// **Nothing is written.** The connection is opened `-readonly`, which is also
/// what makes it safe to read a database the agent itself has open.
///
/// **No token totals are invented.** What comes back is what the agent
/// recorded. Neither tool publishes an allowance to measure it against — that
/// ceiling is the user's own budget from Settings, applied a layer up.
class AgentSessionStore implements AgentUsageReader {
  AgentSessionStore({
    required this.databasePath,
    required this.displayName,
    this.modelCatalogPath,
    this.authPath,
    Logger? logger,
    String sqlitePath = '/usr/bin/sqlite3',
  })  : _sqlite = sqlitePath,
        _log = logger ?? Logger('agent.store');

  /// The agent's SQLite file, absolute.
  final String databasePath;

  /// The tool's cached model catalogue, which carries each model's published
  /// context window. Null when the agent keeps no such file.
  final String? modelCatalogPath;

  /// Used in the sentence shown when there is nothing to report.
  final String displayName;

  final String _sqlite;
  final Logger _log;

  /// True when this agent has a session store on this Mac at all.
  @override
  bool get isAvailable => File(databasePath).existsSync();

  /// Where the tool keeps its sign-in, if it has one. Null when it does not.
  ///
  /// Watched alongside the database because a sign-in changes whose figures
  /// these are, and that should land on the rail without waiting for the
  /// user to open the tool or for the next poll.
  final String? authPath;

  /// When the store last changed, for deciding a cached reading is stale.
  ///
  /// The later of the database and the sign-in file: either one moving is a
  /// reason to read again.
  @override
  DateTime? get changedAt => newestOf([databasePath, ?authPath]);

  /// The newest modification among [paths], skipping any that do not exist.
  static DateTime? newestOf(Iterable<String> paths) {
    DateTime? newest;
    for (final path in paths) {
      // A missing path does not throw here: it stats as "not found" with an
      // epoch date, which would otherwise count as a real, ancient change.
      final stat = FileStat.statSync(path);
      if (stat.type == FileSystemEntityType.notFound) continue;
      final modified = stat.modified;
      if (newest == null || modified.isAfter(newest)) newest = modified;
    }
    return newest;
  }

  /// Totals per model over the last [window].
  ///
  /// Every token column is summed, cache reads included. They are what the
  /// allowance is actually spent on — a session dominated by cache reads is
  /// the normal case for these tools, and counting only input and output would
  /// under-report by an order of magnitude.
  @override
  Future<AgentUsageReading> read({
    Duration window = const Duration(days: 7),
  }) async {
    if (!isAvailable) {
      return AgentUsageReading.unavailable(
        '$displayName has not recorded any sessions on this Mac yet.',
      );
    }

    final since = DateTime.now().subtract(window).millisecondsSinceEpoch;

    final models = await _sessionTotals(since) ?? await _messageTotals(since);

    if (models == null) {
      return AgentUsageReading.unavailable(
        'Could not read $displayName’s session record on this Mac.',
      );
    }

    if (models.isEmpty) {
      return AgentUsageReading.unavailable(
        '$displayName has not been used in the last ${window.inDays} days.',
      );
    }

    // The query is ordered by recency, so the first row is the model the most
    // recent session ran on — the one in use now.
    final active = await _withContext(models.first);

    final byVolume = [...models]..sort((a, b) => b.tokens.compareTo(a.tokens));
    return AgentUsageReading(models: byVolume, active: active);
  }

  /// Whether the session table carries its own token columns.
  ///
  /// OpenCode totals each session as it goes and stores the result on the row.
  /// Kilo Code forked before that and keeps only the model, so the same query
  /// fails there with `no such column` — which is indistinguishable, from the
  /// caller, from the store being unreadable. Asking the schema first is what
  /// separates "this tool records totals elsewhere" from "something is wrong".
  Future<bool> _sessionHasTokenColumns() async {
    final columns = await _query('PRAGMA table_info(session);');
    if (columns == null) return false;
    return columns.any((c) => c['name'] == 'tokens_input');
  }

  /// Totals from the session rows themselves — one grouped query.
  ///
  /// Preferred where it works: the store holds every session the user has ever
  /// run, and there is no reason to carry all of it across a process boundary
  /// to add up six columns. Null when the schema cannot answer it.
  Future<List<AgentModelUsage>?> _sessionTotals(int since) async {
    if (!await _sessionHasTokenColumns()) return null;

    final rows = await _query('''
      SELECT model,
             SUM(tokens_input + tokens_output + tokens_reasoning
                 + tokens_cache_read + tokens_cache_write) AS tokens,
             COUNT(*) AS sessions,
             MAX(time_created) AS last_used
      FROM session
      WHERE model IS NOT NULL AND time_created >= $since
      GROUP BY model
      ORDER BY last_used DESC;
    ''');
    if (rows == null) return null;

    final models = <AgentModelUsage>[];
    for (final row in rows) {
      final usage = _toUsage(row);
      if (usage != null) models.add(usage);
    }
    return models;
  }

  /// Totals rebuilt from the assistant turns.
  ///
  /// Where the session row carries no totals, each assistant message still
  /// records the tokens its turn cost. Summing those reproduces the same
  /// figure the tool shows, at the cost of decoding JSON in Dart — which is
  /// why this is the fallback rather than the default.
  ///
  /// Only assistant turns carry a token block; user turns have none, so they
  /// contribute nothing and are skipped rather than counted as zero.
  Future<List<AgentModelUsage>?> _messageTotals(int since) async {
    final rows = await _query('''
      SELECT data, time_created
      FROM message
      WHERE time_created >= $since
      ORDER BY time_created DESC;
    ''');
    if (rows == null) return null;

    final totals = <String, AgentModelUsage>{};
    for (final row in rows) {
      final raw = row['data'];
      if (raw is! String) continue;

      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;

      final id = decoded['modelID'];
      final tokens = decoded['tokens'];
      if (id is! String || tokens is! Map<String, dynamic>) continue;

      final created = row['time_created'];
      final at = created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0);

      final existing = totals[id];
      totals[id] = AgentModelUsage(
        model: id,
        provider: decoded['providerID'] is String
            ? decoded['providerID'] as String
            : 'unknown',
        tokens: (existing?.tokens ?? 0) + _tokenSum(tokens),
        sessions: (existing?.sessions ?? 0) + 1,
        lastUsedAt: existing == null || at.isAfter(existing.lastUsedAt)
            ? at
            : existing.lastUsedAt,
      );
    }

    // Newest first, matching the order the grouped query returns, so the
    // caller can keep treating the first entry as the model in use.
    return totals.values.toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
  }

  /// Every token a turn spent, cache included.
  ///
  /// Cache reads are what these tools spend most of their allowance on, so
  /// counting only input and output would under-report by an order of
  /// magnitude — the same rule the session-column query follows.
  static int _tokenSum(Map<String, dynamic> tokens) {
    int number(Object? v) => v is num ? v.toInt() : 0;
    final cache = tokens['cache'];
    return number(tokens['input']) +
        number(tokens['output']) +
        number(tokens['reasoning']) +
        (cache is Map<String, dynamic>
            ? number(cache['read']) + number(cache['write'])
            : 0);
  }

  /// Adds the live context figure to the model in use.
  ///
  /// Separate from the totals query because it answers a different question.
  /// The totals say how much a model has been used this week; this says how
  /// full the conversation on screen is right now — which is the number the
  /// tool itself displays, and the one a user checks before deciding whether
  /// to switch models.
  Future<AgentModelUsage> _withContext(AgentModelUsage model) async {
    final rows = await _query('''
      SELECT m.data AS data
      FROM message m
      JOIN session s ON s.id = m.session_id
      ORDER BY m.time_created DESC
      LIMIT 40;
    ''');
    if (rows == null) return model;

    // The newest *assistant* turn carries the running total; user turns carry
    // no token count at all. A short scan back covers a tail of user messages
    // and tool parts without reading the whole table.
    for (final row in rows) {
      final raw = row['data'];
      if (raw is! String) continue;

      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      if (decoded['role'] != 'assistant') continue;

      final tokens = decoded['tokens'];
      if (tokens is! Map<String, dynamic>) continue;
      final total = tokens['total'];
      if (total is! num || total <= 0) continue;

      final modelId = decoded['modelID'];
      final providerId = decoded['providerID'];
      if (modelId is! String || providerId is! String) continue;

      return AgentModelUsage(
        model: modelId,
        provider: providerId,
        tokens: model.tokens,
        sessions: model.sessions,
        lastUsedAt: model.lastUsedAt,
        contextTokens: total.toInt(),
        contextLimit: await _contextLimit(providerId, modelId),
      );
    }

    return model;
  }

  /// The published context window for one model, from the tool's own cache.
  ///
  /// Null when the catalogue is missing or does not list the model — in which
  /// case the context figure is still reported, just without a percentage.
  /// Inventing a limit to get a bar would be worse than having no bar.
  Future<int?> _contextLimit(String providerId, String modelId) async {
    final path = modelCatalogPath;
    if (path == null) return null;

    final catalog = _catalog ??= await _loadCatalog(path);
    final provider = catalog[providerId];
    if (provider is! Map<String, dynamic>) return null;

    final models = provider['models'];
    if (models is! Map<String, dynamic>) return null;

    final model = models[modelId];
    if (model is! Map<String, dynamic>) return null;

    final limit = model['limit'];
    if (limit is! Map<String, dynamic>) return null;

    final context = limit['context'];
    return context is num && context > 0 ? context.toInt() : null;
  }

  Map<String, dynamic>? _catalog;

  Future<Map<String, dynamic>> _loadCatalog(String path) async {
    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (e) {
      _log.debug('no model catalogue at $path: ${e.runtimeType}');
    }
    return const {};
  }

  /// Turns one grouped row into a reading, or null if it is not usable.
  static AgentModelUsage? _toUsage(Map<String, Object?> row) {
    // `model` is stored as JSON: {"id": ..., "providerID": ..., "variant": ...}
    final raw = row['model'];
    if (raw is! String) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final id = decoded['id'];
    if (id is! String || id.isEmpty) return null;

    final tokens = row['tokens'];
    final sessions = row['sessions'];
    final lastUsed = row['last_used'];

    return AgentModelUsage(
      model: id,
      provider: decoded['providerID'] is String
          ? decoded['providerID'] as String
          : 'unknown',
      tokens: tokens is num ? tokens.toInt() : 0,
      sessions: sessions is num ? sessions.toInt() : 0,
      lastUsedAt: lastUsed is num
          ? DateTime.fromMillisecondsSinceEpoch(lastUsed.toInt())
          : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Runs one statement and decodes the rows, or null if it could not run.
  Future<List<Map<String, Object?>>?> _query(String sql) async {
    ProcessResult result;
    try {
      result = await Process.run(
        _sqlite,
        ['-readonly', '-json', databasePath, sql],
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      _log.warn('could not query $databasePath: ${e.runtimeType}');
      return null;
    }

    if (result.exitCode != 0) {
      _log.warn('sqlite3 exited ${result.exitCode} for $databasePath');
      return null;
    }

    final out = (result.stdout as String).trim();
    // An empty result set prints nothing at all, which is not a failure.
    if (out.isEmpty) return const [];

    Object? decoded;
    try {
      decoded = jsonDecode(out);
    } on FormatException {
      _log.warn('sqlite3 returned output that was not JSON');
      return null;
    }

    if (decoded is! List) return null;
    return [
      for (final row in decoded)
        if (row is Map<String, dynamic>) row,
    ];
  }
}
