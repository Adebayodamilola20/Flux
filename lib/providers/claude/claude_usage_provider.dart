import 'dart:io';

import '../../core/logger.dart';
import '../../models/active_session.dart';
import '../../models/app_settings.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_data.dart';
import '../../models/usage_failure.dart';
import '../../models/usage_window.dart';
import '../../services/connection_store.dart';
import '../../services/native/native_bridge.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'claude_admin_api_source.dart';
import 'claude_local_source.dart';

/// Claude usage, assembled from every legitimate source available.
///
/// Two sources, in order of authority:
///
/// 1. **Anthropic Admin API** (optional, provider-reported) — the only public,
///    supported endpoint for account-level Claude usage. It reports
///    organization API consumption. Requires an Admin API key held in the
///    macOS Keychain.
/// 2. **Local Claude Code transcripts** (always available when Claude Code is
///    installed) — token counts this Mac actually generated, measured against a
///    user-configured budget.
///
/// Anthropic publishes no OAuth flow or API for Claude subscription and Claude
/// Code plan limits, so this provider does not pretend to have one. Connecting
/// opens Anthropic's own console in the browser, where the user creates an
/// Admin API key and pastes it back — a key, never a password. The app does not
/// scrape the Claude web app, call undocumented endpoints, read browser
/// cookies, or touch Claude Code's own credential store.
class ClaudeUsageProvider implements UsageProvider {
  ClaudeUsageProvider({
    required NativeBridge native,
    required ConnectionStore connectionStore,
    ClaudeLocalSource? localSource,
    ClaudeAdminApiSource? apiSource,
    Logger? logger,
  })  : _native = native,
        _connections = connectionStore,
        _local = localSource ?? ClaudeLocalSource(),
        _api = apiSource ?? ClaudeAdminApiSource(),
        _log = logger ?? const Logger('claude'),
        _connection = ProviderConnection.notConnected(ProviderCatalog.claude.id);

  /// Keychain entry holding the Anthropic Admin API key.
  static const String adminKeyKeychainId = 'anthropic.admin.key';

  /// Where the user creates that key. Opened in their default browser so they
  /// authenticate with Anthropic directly, never through this app.
  static final Uri consoleUrl =
      Uri.parse('https://console.anthropic.com/settings/admin-keys');

  /// Executable names that indicate an active Claude CLI session.
  static const List<String> _processNames = ['claude'];

  final NativeBridge _native;
  final ConnectionStore _connections;
  final ClaudeLocalSource _local;
  final ClaudeAdminApiSource _api;
  final Logger _log;

  ProviderConnection _connection;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.claude;

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  String get sourceDescription =>
      'Local Claude Code session transcripts, plus the Anthropic Admin API '
      'when an admin key is connected.';

  @override
  ProviderConnection get connection => _connection;

  /// Deliberately false.
  ///
  /// This provider will not report a usage figure the user has not signed in
  /// for. Counting tokens out of local Claude Code transcripts produces a
  /// number, but it is this app's arithmetic against a budget the user typed
  /// in — not what Anthropic says the account has consumed — and showing it on
  /// the rail next to a percentage invites it to be read as the latter.
  ///
  /// Local session detection is still used, but only to report that a process
  /// is running. That is an observation, not a usage claim.
  @override
  bool get supportsLocalOnly => false;

  // MARK: - Connection lifecycle

  @override
  Future<void> restore() async {
    final stored = _connections.load(id);

    // A stored "connected" state is only meaningful if the key is still in the
    // Keychain — the user may have revoked it from Keychain Access directly.
    if (stored.status == ConnectionStatus.connected &&
        await _adminKey() == null) {
      _log.warn('stored Claude connection has no key; downgrading');
      _connection = stored.copyWith(
        status: supportsLocalOnly
            ? ConnectionStatus.limited
            : ConnectionStatus.notConnected,
        message: 'The saved admin key is no longer in the Keychain.',
      );
      await _connections.save(_connection);
      return;
    }

    _connection = stored;
  }

  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) async {
    final opened = await launchUrl(consoleUrl);

    if (!opened) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'Could not open your browser. '
            'Visit console.anthropic.com to create an admin key.',
      ));
    }

    // The flow finishes when the user pastes the key they just created, which
    // arrives via completeAuthentication.
    return _update(_connection.copyWith(
      status: ConnectionStatus.connecting,
      message: 'Create an Admin API key in the browser, then paste it here.',
      clearAccountLabel: true,
    ));
  }

  @override
  Future<ProviderConnection> completeAuthentication(String payload) async {
    final key = payload.trim();
    if (key.isEmpty) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'No key was entered.',
      ));
    }

    // Verify against the real API before storing, so a mistyped key fails here
    // rather than silently producing an empty rail later.
    try {
      await _api.fetchDailyUsage(adminKey: key);
    } on UsageFailure catch (e) {
      _log.warn('key verification failed: ${e.kind.name}');
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: e.message,
      ));
    }

    final written = await _native.writeSecret(adminKeyKeychainId, key);
    if (!written) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'The key could not be saved to your Keychain.',
      ));
    }

    return _update(ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      accountLabel: 'Anthropic admin key',
    ));
  }

  @override
  Future<ProviderConnection> enableLocalOnly() async {
    // No unsigned-in path: usage comes from Anthropic or it is not shown.
    return _update(_connection.copyWith(
      status: ConnectionStatus.error,
      message: 'Claude usage requires signing in to your Anthropic account.',
    ));
  }

  @override
  Future<void> disconnect() async {
    await _native.writeSecret(adminKeyKeychainId, null);
    await _connections.clear(id);
    _connection = ProviderConnection.notConnected(id);
  }

  Future<ProviderConnection> _update(ProviderConnection next) async {
    _connection = next;
    // "connecting" is a transient step in a flow the user may abandon; only
    // settled states are worth persisting.
    if (next.status != ConnectionStatus.connecting) {
      await _connections.save(next);
    }
    return next;
  }

  // MARK: - Usage

  @override
  Future<bool> isAvailable() async {
    if (_local.isAvailable) return true;
    return await _adminKey() != null;
  }

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    if (_connection.status == ConnectionStatus.notConnected) {
      throw const UsageFailure(
        UsageFailureKind.notConfigured,
        'Claude is not connected.',
        hint: 'Connect Claude to start tracking usage.',
      );
    }

    // Every usage figure this provider reports comes from Anthropic. Without a
    // key there is nothing legitimate to show, and the rail says "not
    // connected" rather than filling the gap with local arithmetic.
    final adminKey = await _adminKey();
    if (adminKey == null) {
      throw const UsageFailure(
        UsageFailureKind.authentication,
        'Sign in to Anthropic to see your Claude usage.',
        hint: 'Connect Claude to add an Admin API key from your account.',
      );
    }

    final windows = <UsageWindow>[];
    final apiWindow = await _api.fetchDailyUsage(adminKey: adminKey);
    if (apiWindow != null) windows.add(apiWindow);

    if (windows.isEmpty) {
      throw const UsageFailure(
        UsageFailureKind.notConfigured,
        'Anthropic reported no usage for this account yet.',
      );
    }

    // Local session detection is an observation about this machine — which
    // project is open, whether the process is busy — never a usage figure.
    var sessions = const <ActiveSession>[];
    if (_local.isAvailable) {
      try {
        final local = await _local.load(settings);
        sessions = await _resolveSessions(local);
      } on FileSystemException catch (e) {
        // Losing the session row must not lose the usage the user signed in
        // for, so this degrades silently.
        _log.warn('local session scan failed: ${e.osError?.message}');
      }
    }

    const notes = <String>[
      'Figures reported by the Anthropic API for your account.',
    ];
    const status = ConnectionStatus.connected;

    // Keep the persisted link in step with what the fetch actually achieved,
    // so the connect screen never claims more than the rail is showing.
    if (_connection.status != status) {
      await _update(_connection.copyWith(status: status));
    }

    return UsageData(
      providerId: id,
      providerName: displayName,
      windows: windows,
      connection: status,
      fetchedAt: DateTime.now(),
      sessions: sessions,
      accountLabel: _connection.accountLabel,
      notes: notes,
    );
  }

  /// Combines the newest local transcript turn with a live process scan.
  ///
  /// The transcript tells us *what* was worked on; the process scan tells us
  /// whether a session is still running and which terminal owns it. Only the
  /// working directory and host application are read — never transcript
  /// content beyond the token counts already aggregated.
  Future<List<ActiveSession>> _resolveSessions(ClaudeLocalUsage local) async {
    final latest = local.latestEvent;
    final processes = await _native.findProcesses(_processNames);

    if (processes.isEmpty) {
      // Nothing running. A recent transcript alone is history, not activity.
      return const [];
    }

    final title = latest?.workingDirectory != null
        ? _projectName(latest!.workingDirectory!)
        : displayName;

    // A turn within the last couple of minutes is what distinguishes a session
    // that is working from one that is sitting at a prompt.
    final lastActivity = latest?.timestamp;
    final isBusy = lastActivity != null &&
        DateTime.now().difference(lastActivity) < const Duration(minutes: 2);

    return [
      for (final process in processes)
        ActiveSession(
          title: title,
          host: process.host,
          command: 'Claude Code',
          pid: process.pid,
          lastActivity: lastActivity,
          isBusy: isBusy,
        ),
    ];
  }

  static String _projectName(String path) {
    final segments =
        path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? path : segments.last;
  }

  Future<String?> _adminKey() async {
    final key = await _native.readSecret(adminKeyKeychainId);
    if (key == null || key.trim().isEmpty) return null;
    return key.trim();
  }

  @override
  Future<void> dispose() async {
    _api.close();
  }
}
