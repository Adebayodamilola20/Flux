import 'dart:async';

import '../../core/logger.dart';
import '../../models/active_session.dart';
import '../../models/app_settings.dart';
import '../../models/connection_status.dart';
import '../../models/provider_connection.dart';
import '../../models/usage_data.dart';
import '../../models/usage_source.dart';
import '../../models/usage_window.dart';
import '../../services/connection_store.dart';
import '../../services/native/native_bridge.dart';
import '../usage_provider.dart';
import 'agent_session_store.dart';

/// A coding agent that routes to whichever model the user has chosen.
///
/// **What is measured, and against what.** These tools are not an account with
/// an allowance; they are a client pointed at somebody else's model. Neither
/// OpenCode nor Kilo Code publishes a limit, and the model behind them changes
/// whenever the user changes it. So the figure is tokens actually spent — from
/// the agent's own session record, not an estimate — measured against the
/// weekly budget in Settings. It is labelled [UsageSource.localTracking]
/// because the ceiling is the user's, not the provider's.
///
/// **The model is part of the reading.** Running out on one model and moving to
/// another is the normal way these tools are used, and it makes the previous
/// figure meaningless: a fresh model has its own allowance and its own spend.
/// So the window is named for the model in use, and the total is that model's
/// alone. Switching does not zero a counter — it reports the model now in use,
/// which is a different number and usually a much smaller one.
abstract class AgentUsageProvider implements UsageProvider {
  AgentUsageProvider({
    required this.native,
    required ConnectionStore connectionStore,
    AgentUsageReader? store,
    Logger? logger,
  })  : _connections = connectionStore,
        log = logger ?? const Logger('agent') {
    _connection = ProviderConnection.notConnected(descriptor.id);
    _store = store ?? buildStore();
  }

  final NativeBridge native;
  final Logger log;
  final ConnectionStore _connections;

  late final AgentUsageReader _store;
  late ProviderConnection _connection;

  /// Exposed for subclasses and tests.
  AgentUsageReader get store => _store;

  /// Builds the reader this agent uses. Overridden per agent.
  AgentUsageReader buildStore();

  /// The window the rail reports over. A week matches how these tools' upstream
  /// allowances are usually granted, and matches Claude's weekly window so the
  /// two rings on one rail mean the same span of time.
  Duration get window => const Duration(days: 7);

  // MARK: - UsageProvider

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  ProviderConnection get connection => _connection;

  @override
  bool get supportsLocalOnly => true;

  @override
  Future<bool> isAvailable() async => _store.isAvailable;

  @override
  Future<void> restore() async {
    // No credential anywhere in this provider, so there is nothing to verify
    // and nothing that can go missing. The stored state is the state.
    _connection = _connections.load(id);
  }

  @override
  Future<ProviderConnection> enableLocalOnly() async {
    if (!_store.isAvailable) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.error,
        message: '${descriptor.displayName} has not recorded any sessions on '
            'this Mac. Run it once, then add it again.',
      ));
    }

    final reading = await _store.read(window: window);

    return _update(ProviderConnection(
      providerId: id,
      // `limited`, not `connected`: the tokens are the agent's own record, but
      // the ceiling they are shown against is the user's budget rather than a
      // limit anyone published. Calling that "connected" would overstate it.
      status: ConnectionStatus.limited,
      connectedAt: DateTime.now(),
      accountLabel: reading.active?.label,
    ));
  }

  /// Nothing to open and nothing to paste: adding it is the whole flow.
  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) =>
      enableLocalOnly();

  @override
  Future<ProviderConnection> completeAuthentication(String payload) async =>
      _connection;

  @override
  Future<void> disconnect() async {
    await _connections.markDisconnected(id);
    _connection = ProviderConnection.notConnected(id);
  }

  /// Re-reads when the agent writes a session.
  ///
  /// This is what makes a model switch land on the rail without waiting for a
  /// poll: the switch becomes visible the moment the first session on the new
  /// model is recorded, which is the earliest it is knowable at all.
  @override
  Stream<void>? get changes {
    if (!_store.isAvailable) return null;

    return Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => _store.changedAt)
        .where((at) {
          if (at == null) return false;
          final seen = _seenChangeAt;
          _seenChangeAt = at;
          // The first reading establishes the baseline rather than counting as
          // a change; otherwise every launch fires a redundant fetch.
          return seen != null && at.isAfter(seen);
        })
        .map((_) {});
  }

  DateTime? _seenChangeAt;

  /// Cheap to read — a grouped query against a local file — so there is no
  /// reason to let a switch sit unnoticed for the user's whole interval.
  @override
  Duration? get preferredRefreshInterval => const Duration(seconds: 30);

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    final reading = await _store.read(window: window);
    final active = reading.active;

    if (active == null) {
      return UsageData(
        providerId: id,
        providerName: displayName,
        windows: const [],
        connection: _connection.status,
        fetchedAt: DateTime.now(),
        usageUnavailableReason: reading.unavailableReason ??
            '${descriptor.displayName} has recorded no sessions to measure.',
        // Retrying re-reads a record that is empty, and will stay empty until
        // the tool is used. Saying so — and saying what to do instead — is the
        // whole of what the user needs here.
        usageUnavailableIsPermanent: true,
        fixItSteps: fixItSteps,
      );
    }

    // Only the model in use. The others are still in the reading, and are
    // listed as notes so a user who has been switching can see where their
    // week actually went — but the ring is about the model they are on.
    final others = reading.models.where((m) => m.model != active.model);

    if (_connection.accountLabel != active.label) {
      log.info('${descriptor.displayName} is now on ${active.label}');
      await _update(_connection.copyWith(accountLabel: active.label));
    }

    final context = active.contextTokens;
    final contextLimit = active.contextLimit;

    return UsageData(
      providerId: id,
      providerName: displayName,
      connection: _connection.status,
      fetchedAt: DateTime.now(),
      accountLabel: active.label,
      windows: [
        // First, so it is the ring: this is the figure the tool itself shows,
        // and the one that decides whether the next prompt fits. Reporting the
        // week here instead is what made the rail read 0% while OpenCode's own
        // status line read 5% — two true numbers about different things.
        if (context != null)
          UsageWindow(
            id: 'context',
            label: active.label,
            consumed: context.toDouble(),
            // The model's published context window, from the tool's own
            // catalogue. Absent for a model the catalogue does not list, in
            // which case the count is shown without a percentage rather than
            // measured against something invented.
            limit: contextLimit?.toDouble(),
            unit: 'tokens',
            source: UsageSource.officialCli,
          ),
        UsageWindow(
          id: 'weekly_tokens',
          label: 'This week',
          consumed: active.tokens.toDouble(),
          // No limit, deliberately. Neither tool publishes a weekly allowance,
          // and the budget this used to be divided by was a number the app
          // invented — so it is reported as the count it is, and the bar is
          // left off rather than drawn against nothing.
          limit: null,
          unit: 'tokens',
          source: UsageSource.localTracking,
        ),
      ],
      notes: [
        if (context != null && contextLimit == null)
          'No published context window for ${active.label}, so this is a count '
              'rather than a percentage.',
        'On ${active.label}, served by ${active.provider}. '
            '${active.sessions} session${active.sessions == 1 ? '' : 's'} in '
            'the last ${window.inDays} days.',
        if (others.isNotEmpty)
          'Also used this week: '
              '${others.map((m) => m.label).take(3).join(', ')}.',
        '${descriptor.displayName} publishes no weekly allowance, so the '
            'weekly figure is a count rather than a percentage.',
      ],
    );
  }

  /// Short, concrete things the user can do when there is nothing to report.
  ///
  /// Written as instructions rather than diagnosis: a person looking at an
  /// empty card wants to know what to press, not what the app concluded.
  List<String> get fixItSteps => [
        'Open a terminal and run $executableName.',
        'Send it one message, so it records a session.',
        'Come back here — the figure appears on its own.',
      ];

  /// What the user types to start this tool.
  String get executableName => descriptor.id;

  /// These agents are measured from what they wrote, not from what is running,
  /// so there is no process to report.
  @override
  Future<List<ActiveSession>> detectActivity() async => const [];

  /// Nothing is held between reads — every fetch is a fresh query — so a
  /// deliberate refresh has nothing to discard.
  @override
  void invalidateCaches() {}

  @override
  Future<void> dispose() async {}

  Future<ProviderConnection> _update(ProviderConnection next) async {
    _connection = next;
    await _connections.save(next);
    return next;
  }
}
