import 'dart:io';

import '../../core/formatting.dart';
import '../../core/logger.dart';
import '../../models/active_session.dart';
import '../../models/app_settings.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_data.dart';
import '../../models/usage_failure.dart';
import '../../services/connection_store.dart';
import '../../services/native/native_bridge.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'claude_account_source.dart';
import 'claude_admin_api_source.dart';
import 'claude_live_source.dart';
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
    ClaudeAccountSource? accountSource,
    ClaudeLiveUsageSource? liveSource,
    Logger? logger,
  })  : _native = native,
        _connections = connectionStore,
        _account = accountSource ?? ClaudeAccountSource(),
        _live = liveSource ??
            ClaudeLiveUsageSource(
              keychainReader: native.readClaudeCodeCredentials,
            ),
        _local = localSource ?? ClaudeLocalSource(),
        _api = apiSource ?? ClaudeAdminApiSource(),
        _log = logger ?? const Logger('claude'),
        _connection = ProviderConnection.notConnected(ProviderCatalog.claude.id);

  /// Keychain entry holding the Anthropic Admin API key.
  static const String adminKeyKeychainId = 'anthropic.admin.key';

  /// Where the user creates that key. Opened in their default browser so they
  /// authenticate with Anthropic directly, never through this app.
  /// Anthropic's current console host. `console.anthropic.com` still works but
  /// redirects here, and landing on a redirect makes an already-unfamiliar
  /// destination look like the app sent the user somewhere wrong.
  static final Uri consoleUrl =
      Uri.parse('https://platform.claude.com/settings/admin-keys');

  /// Executable names that indicate an active Claude CLI session.
  static const List<String> _processNames = ['claude'];

  final NativeBridge _native;
  final ConnectionStore _connections;
  final ClaudeAccountSource _account;
  final ClaudeLiveUsageSource _live;
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

  /// True when Claude Code has signed in on this Mac.
  ///
  /// Anthropic publishes no OAuth flow a third party can register for, so
  /// there is no browser step to offer. What there is instead is a session
  /// Claude Code already established, and the account it belongs to.
  @override
  bool get supportsLocalOnly => _account.isAvailable;

  // MARK: - Connection lifecycle

  /// Re-reads as soon as Claude Code rewrites its config, so the rail shows
  /// the newest figures Anthropic has reported rather than waiting for the
  /// next scheduled refresh.
  @override
  Stream<void>? get changes => _account.watch();

  /// Claude usage moves with every prompt, and reading it is one small GET
  /// against Anthropic's own endpoint. Polling it on the user's general
  /// interval — five minutes by default — means the rail disagrees with
  /// `claude /usage` for most of every five minutes, which is the whole
  /// complaint. The file watch catches Claude Code's own refreshes within a
  /// couple of seconds; this covers the rest.
  @override
  Duration? get preferredRefreshInterval => const Duration(seconds: 30);

  /// Lets a user who has just approved the Keychain prompt — or just signed in
  /// to Claude Code — get a live figure now, instead of waiting out the
  /// back-off that stops a declined dialog from reappearing every poll.
  @override
  void invalidateCaches() => _live.reset();

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
    final reading = await _account.read();

    if (!reading.isSignedIn) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: 'No signed-in Claude account was found on this Mac. '
            'Sign in to Claude Code, then connect again.',
      ));
    }

    // `connected`, because these are Anthropic's own figures for a real
    // account — not an estimate this app produced.
    return _update(ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      accountLabel: reading.email,
    ));
  }

  @override
  Future<void> disconnect() async {
    await _native.writeSecret(adminKeyKeychainId, null);
    // A record, not an erasure — see ConnectionStore.markDisconnected.
    await _connections.markDisconnected(id);
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

  /// Claude Code sessions running on this Mac.
  ///
  /// Needs no connection, no key, and no account: it is a process scan plus the
  /// working directory of the most recent local transcript. This is what makes
  /// Claude useful on the rail even though Anthropic offers no account sign-in
  /// for usage.
  @override
  Future<List<ActiveSession>> detectActivity() async {
    if (!_local.isAvailable) {
      // No transcripts to name a project from, but a running process is still
      // worth reporting.
      final processes = await _native.findProcesses(_processNames);
      return [
        for (final process in processes)
          ActiveSession(
            title: displayName,
            host: process.host,
            command: 'Claude Code',
            pid: process.pid,
          ),
      ];
    }

    try {
      final local = await _local.load(const AppSettings());
      return await _resolveSessions(local);
    } on FileSystemException catch (e) {
      _log.warn('local session scan failed: ${e.osError?.message}');
      return const [];
    }
  }

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    if (!_connection.isConnected) {
      throw const UsageFailure(
        UsageFailureKind.notConfigured,
        'Claude is not connected.',
        hint: 'Connect Claude to see your subscription usage.',
      );
    }

    final reading = await _account.read();

    if (!reading.isSignedIn) {
      await _update(_connection.copyWith(
        status: ConnectionStatus.notConnected,
        message: 'The Claude account on this Mac is signed out.',
      ));
      throw const UsageFailure(
        UsageFailureKind.authentication,
        'The Claude account on this Mac is signed out.',
        hint: 'Sign in to Claude Code, then reconnect.',
      );
    }

    if (reading.email != _connection.accountLabel) {
      await _update(_connection.copyWith(accountLabel: reading.email));
    }

    final plan = ClaudeAccountSource.planLabel(reading.plan);

    // Live first. `~/.claude.json` is a cache Claude Code last wrote; the live
    // endpoint returns the same server-computed figure, current now, using the
    // session Claude Code already holds. Prefer it, and fall back to the cache
    // only when the token cannot be used without disturbing Claude Code's own
    // login (expired) or the call cannot be made (offline).
    final (live, failure) = await _live.fetch();
    if (live != null && live.hasUsage) {
      return UsageData(
        providerId: id,
        providerName: displayName,
        windows: live.windows,
        connection: ConnectionStatus.connected,
        fetchedAt: live.fetchedAt ?? DateTime.now(),
        accountLabel: reading.email,
        notes: [
          if (plan != null) plan,
          'Live from Anthropic, just now.',
        ],
      );
    }
    if (failure != null) {
      _log.info('live usage unavailable (${failure.name}); using cache');
    }

    // Why the cached figure is being shown, when there is a reason worth
    // telling the user. Without this the card shows a number that lags the
    // CLI with no explanation, which reads as the app being wrong.
    final fallbackNote = switch (failure) {
      ClaudeLiveFailure.keychainDenied =>
        'Allow access to “Claude Code-credentials” in your Keychain to read '
            'live usage. Showing the last figure Claude Code cached.',
      ClaudeLiveFailure.tokenExpired || ClaudeLiveFailure.unauthorized =>
        'Claude Code’s stored session could not be used for a live reading. '
            'Showing the last figure it cached.',
      ClaudeLiveFailure.network =>
        'Anthropic could not be reached. Showing the last cached figure.',
      _ => null,
    };

    if (!reading.hasUsage) {
      // Signed in, but neither the live call nor the cache has a figure yet.
      // Stated as unavailable rather than backfilled with a number of our own.
      return UsageData(
        providerId: id,
        providerName: displayName,
        windows: const [],
        connection: ConnectionStatus.connected,
        fetchedAt: DateTime.now(),
        accountLabel: reading.email,
        usageUnavailableReason:
            'No usage has been reported for this account yet. Run Claude Code '
            'once to refresh it.',
      );
    }

    final observedAt = reading.fetchedAt;

    return UsageData(
      providerId: id,
      providerName: displayName,
      windows: reading.windows,
      connection: ConnectionStatus.connected,
      fetchedAt: observedAt ?? DateTime.now(),
      accountLabel: reading.email,
      notes: [
        if (plan != null) plan,
        // The figures are Anthropic's, but they arrive through a cache Claude
        // Code refreshes rather than a live call, and the card says so instead
        // of implying the number is current to the second.
        if (observedAt != null)
          'Reported by Anthropic, as of ${Format.relativeTime(observedAt)}.',
        if (fallbackNote != null) fallbackNote,
      ],
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
    _live.close();
  }
}
