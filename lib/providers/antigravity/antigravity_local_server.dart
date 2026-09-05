import 'dart:convert';
import 'dart:io';

import '../../core/logger.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';

/// A reading taken from Antigravity's own language server.
class AntigravityServerReading {
  const AntigravityServerReading({required this.windows, required this.observedAt});

  final List<UsageWindow> windows;
  final DateTime observedAt;

  bool get hasUsage => windows.isNotEmpty;
}

/// Where the language server is listening, and the token that gets past its
/// cross-site guard.
class AntigravityEndpoint {
  const AntigravityEndpoint({required this.ports, required this.csrfToken});

  /// Every port the process holds open. It listens on more than one and only
  /// one of them answers this call, so all of them are tried.
  final List<int> ports;
  final String csrfToken;
}

/// Reads the Antigravity quota from the language server already running on
/// this Mac.
///
/// **Why this replaces driving the CLI.** The figure used to be read by
/// starting `agy` under a pseudo-terminal, waiting for it to sign itself in
/// and draw its usage panel, and scraping the result — the better part of a
/// minute, a real process launch, and a browser window if the CLI decided it
/// needed to authenticate. That is why the number could only be fetched when
/// the user explicitly asked, and why it was usually hours old.
///
/// Antigravity already runs a language server locally and that server answers
/// the same question over HTTP in a few milliseconds. Nothing is launched,
/// nothing is scraped, and the figure is the one the server would give its own
/// UI.
///
/// **How it is found.** The server is started with its CSRF token on the
/// command line and its port assigned at random, so the process table is the
/// only source of truth: find the process, take the token from its arguments,
/// ask the kernel which ports that PID is listening on.
///
/// **What it cannot do.** If Antigravity is not running there is no server to
/// ask. That is not a failure to report loudly — it is simply a moment when
/// the live figure is unavailable and the last one stands.
class AntigravityLocalServer {
  AntigravityLocalServer({Logger? logger, HttpClient? httpClient})
      : _log = logger ?? const Logger('antigravity.server'),
        _client = httpClient ?? _defaultClient();

  /// The header the server wants its token in. It never says which header it
  /// wanted — only "missing CSRF token" — so this is not guessable from the
  /// error.
  static const String csrfHeader = 'x-codeium-csrf-token';

  /// The RPC the server answers quota questions on.
  static const String servicePath =
      '/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary';

  final Logger _log;
  final HttpClient _client;

  static HttpClient _defaultClient() {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    // The server presents a certificate it signed itself, for a connection
    // that never leaves the machine. Accepting it is scoped to loopback so
    // this cannot become a general "trust anything" client.
    client.badCertificateCallback = (_, host, __) =>
        host == '127.0.0.1' || host == 'localhost';
    return client;
  }

  /// Locates the running language server, or null when Antigravity is closed.
  Future<AntigravityEndpoint?> discover() async {
    final table = await _run('/bin/ps', ['-axww', '-o', 'pid=,command=']);
    if (table == null) return null;

    for (final line in const LineSplitter().convert(table)) {
      if (!line.contains('language_server') || !line.contains('--csrf_token')) {
        continue;
      }
      final token = flagValue('--csrf_token', line);
      final pid = int.tryParse(line.trimLeft().split(RegExp(r'\s+')).first);
      if (token == null || pid == null) continue;

      final ports = await listeningPorts(pid);
      if (ports.isEmpty) continue;
      return AntigravityEndpoint(ports: ports, csrfToken: token);
    }
    return null;
  }

  /// Pulls `--flag value` or `--flag=value` out of a command line.
  static String? flagValue(String flag, String line) {
    final match = RegExp('$flag[= ]([^ ]+)').firstMatch(line);
    final value = match?.group(1);
    return (value == null || value.isEmpty) ? null : value;
  }

  /// The TCP ports a PID is listening on.
  Future<List<int>> listeningPorts(int pid) async {
    // `-a` is load-bearing: without it lsof ORs the filters instead of ANDing
    // them, and the answer includes ports belonging to other processes.
    final output = await _run(
      '/usr/sbin/lsof',
      ['-nP', '-a', '-p', '$pid', '-iTCP', '-sTCP:LISTEN'],
    );
    if (output == null) return const [];
    return parsePorts(output);
  }

  static List<int> parsePorts(String lsofOutput) {
    final ports = <int>{};
    for (final line in const LineSplitter().convert(lsofOutput)) {
      final match = RegExp(r'(?:\S+):(\d+)\s+\(LISTEN\)').firstMatch(line);
      final port = int.tryParse(match?.group(1) ?? '');
      if (port != null) ports.add(port);
    }
    return ports.toList();
  }

  /// Asks the server for the current quota.
  Future<AntigravityServerReading?> read() async {
    final endpoint = await discover();
    if (endpoint == null) {
      _log.debug('no language server running; Antigravity is closed');
      return null;
    }

    for (final port in endpoint.ports) {
      final windows = await _ask(port, endpoint.csrfToken);
      if (windows != null && windows.isNotEmpty) {
        _log.debug('read ${windows.length} quota window(s) from port $port');
        return AntigravityServerReading(
          windows: windows,
          observedAt: DateTime.now(),
        );
      }
    }
    return null;
  }

  Future<List<UsageWindow>?> _ask(int port, String token) async {
    try {
      final request = await _client
          .postUrl(Uri.parse('https://127.0.0.1:$port$servicePath'))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(csrfHeader, token);
      // Without this the server answers from its own summary cache, so the
      // figure only moved when something else refreshed it — in practice,
      // opening Antigravity's Models & Usage panel and pressing refresh there.
      request.write('{"forceRefresh":true}');

      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      return parseWindows(body);
    } catch (e) {
      _log.debug('port $port did not answer: ${e.runtimeType}');
      return null;
    }
  }

  /// Turns the quota summary into windows.
  ///
  /// The server reports what is **left**; every figure in this app is what has
  /// been spent, so the fraction is inverted here rather than in the UI, where
  /// a percentage's meaning would then depend on which provider produced it.
  static List<UsageWindow> parseWindows(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];

    final response = decoded['response'];
    if (response is! Map<String, dynamic>) return const [];
    final groups = response['groups'];
    if (groups is! List) return const [];

    final windows = <UsageWindow>[];
    for (final group in groups) {
      if (group is! Map<String, dynamic>) continue;
      final groupName = group['displayName'];
      final buckets = group['buckets'];
      if (buckets is! List) continue;

      for (final bucket in buckets) {
        if (bucket is! Map<String, dynamic>) continue;
        final remaining = (bucket['remainingFraction'] as num?)?.toDouble();
        if (remaining == null || remaining < 0 || remaining > 1) continue;

        // The group names the models; the bucket only ever says "Weekly Limit
        // Remaining", which is the same text for every one of them.
        final label = (groupName is String && groupName.isNotEmpty)
            ? groupName
            : (bucket['displayName'] as String? ?? 'Usage');

        windows.add(UsageWindow(
          id: (bucket['bucketId'] as String?) ?? label,
          label: label,
          consumed: ((1 - remaining) * 100).round(),
          limit: 100,
          unit: 'percent',
          source: UsageSource.officialApi,
          observedAt: DateTime.now(),
          resetsAt: _parseTime(bucket['resetTime']),
        ));
      }
    }
    return windows;
  }

  static DateTime? _parseTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  Future<String?> _run(String executable, List<String> arguments) async {
    try {
      final result = await Process.run(executable, arguments)
          .timeout(const Duration(seconds: 6));
      if (result.exitCode != 0) return null;
      return result.stdout as String;
    } catch (e) {
      _log.debug('$executable failed: ${e.runtimeType}');
      return null;
    }
  }
}
