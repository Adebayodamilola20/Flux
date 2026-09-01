import 'dart:async';
import 'dart:io';

import '../../core/formatting.dart';
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
import '../usage_provider.dart';
import 'cli_quota_source.dart';

/// What a CLI-backed provider found.
class CliUsageReading {
  const CliUsageReading({
    required this.windows,
    this.accountLabel,
    this.notes = const [],
    this.unavailableReason,
    this.isPermanent = false,
  });

  const CliUsageReading.unavailable(
    String reason, {
    this.accountLabel,
    this.isPermanent = false,
  })  : windows = const [],
        notes = const [],
        unavailableReason = reason;

  final List<UsageWindow> windows;
  final String? accountLabel;
  final List<String> notes;
  final String? unavailableReason;

  /// True when no amount of retrying can produce a figure.
  final bool isPermanent;

  bool get hasWindows => windows.isNotEmpty;
}

/// A provider whose usage comes from a tool already installed and signed in on
/// this Mac, with no account link of its own.
///
/// **Why there is no sign-in.** Asking the user to authorise this app is only
/// worth doing when it buys something. For these providers it buys nothing: a
/// Google OAuth token names the account but carries no quota, while the tool
/// sitting on the same machine already knows the answer and is already signed
/// in. So the connect step is removed entirely — if the CLI is here, the slot
/// works.
///
/// **Adding is one click.** Because there is nothing to authorise, putting one
/// of these on the rail connects it outright — no Connect button behind the
/// picker, and no browser step. What the app does *not* do is decide for the
/// user which tools belong on their rail: it starts empty.
abstract class CliUsageProvider implements UsageProvider {
  CliUsageProvider({
    required NativeBridge native,
    required ConnectionStore connectionStore,
    CliQuotaSource? source,
    Logger? logger,
  })  : native = native,
        _connections = connectionStore,
        log = logger ?? Logger('cli.${native.hashCode}') {
    _connection = ProviderConnection.notConnected(descriptor.id);
    quota = source ??
        CliQuotaSource(
          native: native,
          executable: executable,
          usageCommand: usageCommand,
          ttl: quotaTtl,
        );
  }

  /// Available to subclasses for process detection.
  final NativeBridge native;
  final Logger log;
  final ConnectionStore _connections;

  /// Drives the CLI's usage panel. Created from [executable] and
  /// [usageCommand] unless a subclass supplies its own.
  late final CliQuotaSource quota;

  late ProviderConnection _connection;

  // MARK: - What subclasses define

  /// The CLI that holds this provider's session, e.g. `agy`.
  String get executable;

  /// The slash command that draws its usage panel, e.g. `/usage`.
  String get usageCommand;

  /// How long a reading stays good.
  Duration get quotaTtl => const Duration(minutes: 5);

  /// Executables whose presence means a session is running locally.
  List<String> get processNames => [executable];

  /// How a detected process is labelled.
  String get activityLabel => '${descriptor.displayName} CLI';

  /// Directory the CLI writes to as it works, relative to the home directory.
  ///
  /// Used for one thing: knowing that a cached reading has been overtaken by a
  /// session. Without it the figure sits at its last value until the cache
  /// expires, which is what makes a user who has just finished a long session
  /// conclude the app is broken.
  ///
  /// Null when the tool has no such directory.
  String? get activityDirectory => null;

  /// Reads usage. The default drives the CLI's usage panel; a provider whose
  /// tool has no such panel overrides this to explain that instead.
  Future<CliUsageReading> readUsage(AppSettings settings) async {
    final reading = await quota.read(staleIfOlderThan: _lastActivity());

    if (reading.hasUsage) {
      final observedAt = reading.observedAt;
      return CliUsageReading(
        windows: reading.windows,
        accountLabel: reading.accountLabel,
        notes: [
          if (reading.planLabel != null) reading.planLabel!,
          if (observedAt != null)
            'Read from the ${descriptor.displayName} usage panel, '
                '${Format.relativeTime(observedAt)}.',
        ],
      );
    }

    // The probe produced nothing this time. That is common and usually
    // temporary: driving a real CLI under a pseudo-terminal takes the better
    // part of a minute and loses to a busy machine, a slow start, or a panel
    // that was still drawing. Throwing away a figure that was read correctly
    // ten minutes ago and replacing it with "usage unavailable" is what made a
    // working slot appear to break on its own and then offer a Retry that
    // fixed nothing. The last good reading is served instead, and said to be
    // what it is.
    final previous = quota.cached;
    if (previous != null &&
        previous.hasUsage &&
        reading.failure != CliQuotaFailure.notInstalled) {
      final observedAt = previous.observedAt;
      return CliUsageReading(
        windows: previous.windows,
        accountLabel: previous.accountLabel,
        notes: [
          if (previous.planLabel != null) previous.planLabel!,
          if (observedAt != null)
            'Last read from the ${descriptor.displayName} usage panel '
                '${Format.relativeTime(observedAt)}. '
                '${_retryNote(reading.failure)}',
        ],
      );
    }

    return unavailableFor(reading.failure);
  }

  /// One clause explaining why the figure above is not newer.
  String _retryNote(CliQuotaFailure? failure) => switch (failure) {
    CliQuotaFailure.signedOut =>
      'It did not answer just now — if you have signed out, run `$executable` '
          'and sign in again.',
    _ => 'It did not answer just now; this will refresh on its own.',
  };

  /// The message for a probe that produced nothing.
  ///
  /// Split out so each reason gets wording the user can act on, instead of one
  /// "usage unavailable" covering three different situations.
  CliUsageReading unavailableFor(CliQuotaFailure? failure) {
    final name = descriptor.displayName;
    return switch (failure) {
      CliQuotaFailure.notInstalled => CliUsageReading.unavailable(
          'The $name CLI is not installed on this Mac. It is the only place '
          '$name reports your limit, so installing it is what puts a figure '
          'here.',
          isPermanent: true,
        ),
      CliQuotaFailure.signedOut => CliUsageReading.unavailable(
          'The $name CLI is not signed in on this Mac. Run `$executable` and '
          'sign in, then refresh.',
        ),
      _ => CliUsageReading.unavailable(
          'The $name CLI did not show its usage panel. It may be busy, or the '
          'panel may have changed.',
        ),
    };
  }

  // MARK: - UsageProvider

  @override
  String get id => descriptor.id;

  @override
  String get displayName => descriptor.displayName;

  @override
  ProviderConnection get connection => _connection;

  /// Always: there is nothing to sign in to, so the local source is the only
  /// source and it is always the one used.
  @override
  bool get supportsLocalOnly => true;

  @override
  Future<bool> isAvailable() => quota.isInstalled;

  /// Loads the stored state, and nothing more.
  ///
  /// Adding a provider is the user's decision — the rail starts empty and they
  /// put things on it. Connecting happens when they do, which is why there is
  /// no second step: see [UsageController.assignSlot].
  @override
  Future<void> restore() async {
    _connection = _connections.load(id);
  }

  /// There is no browser step. Connect and Enable do the same thing, so a user
  /// who presses either gets the same result rather than one of them opening a
  /// consent page that grants nothing.
  @override
  Future<ProviderConnection> connect({required UrlLauncher launchUrl}) =>
      enableLocalOnly();

  @override
  Future<ProviderConnection> enableLocalOnly() async {
    if (!await quota.isInstalled) {
      return _update(_connection.copyWith(
        status: ConnectionStatus.notConnected,
        message: 'The $executable command was not found on this Mac.',
      ));
    }

    return _update(ProviderConnection(
      providerId: id,
      status: ConnectionStatus.connected,
      connectedAt: DateTime.now(),
      accountLabel: quota.cached?.accountLabel ?? _connection.accountLabel,
    ));
  }

  /// Nothing to paste: this provider takes no credential.
  @override
  Future<ProviderConnection> completeAuthentication(String payload) async =>
      _connection;

  @override
  Future<void> disconnect() async {
    quota.invalidate();
    await _connections.markDisconnected(id);
    _connection = ProviderConnection.notConnected(id);
  }

  /// Fires when the CLI writes something, so a session that just ended is
  /// reflected without waiting for the next scheduled poll.
  @override
  Stream<void>? get changes {
    if (activityDirectory == null) return null;
    return _watchActivity();
  }

  Stream<DateTime> _watchActivity({
    Duration interval = const Duration(seconds: 5),
  }) async* {
    DateTime? last = _lastActivity();

    while (true) {
      await Future<void>.delayed(interval);
      final current = _lastActivity();
      if (current == null) continue;
      if (last == null || current.isAfter(last)) {
        last = current;
        yield current;
      }
    }
  }

  /// The newest modification anywhere under [activityDirectory].
  ///
  /// One level deep rather than a full walk: these directories hold a file or
  /// a folder per session, so the newest entry is enough to date the last one,
  /// and this runs on a timer.
  DateTime? _lastActivity() {
    final relative = activityDirectory;
    if (relative == null) return null;

    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final directory = Directory('$home/$relative');
    if (!directory.existsSync()) return null;

    DateTime? newest;
    try {
      for (final entry in directory.listSync(followLinks: false)) {
        final modified = entry.statSync().modified;
        if (newest == null || modified.isAfter(newest)) newest = modified;
      }
    } on FileSystemException {
      return null;
    }
    return newest;
  }

  @override
  Duration? get preferredRefreshInterval => null;

  @override
  void invalidateCaches() => quota.invalidate();

  @override
  Future<List<ActiveSession>> detectActivity() async {
    final processes = await native.findProcesses(processNames);
    return [
      for (final process in processes)
        ActiveSession(
          title: descriptor.displayName,
          host: process.host,
          command: activityLabel,
          pid: process.pid,
          isBusy: true,
        ),
    ];
  }

  @override
  Future<UsageData> fetchUsage(AppSettings settings) async {
    if (!_connection.isConnected) {
      throw UsageFailure(
        UsageFailureKind.notConfigured,
        '${descriptor.displayName} is not connected.',
      );
    }

    final reading = await readUsage(settings);

    if (reading.accountLabel != null &&
        reading.accountLabel != _connection.accountLabel) {
      await _update(_connection.copyWith(accountLabel: reading.accountLabel));
    }

    return UsageData(
      providerId: id,
      providerName: displayName,
      windows: reading.windows,
      connection: ConnectionStatus.connected,
      fetchedAt: DateTime.now(),
      accountLabel: reading.accountLabel ?? _connection.accountLabel,
      notes: reading.notes,
      usageUnavailableReason: reading.hasWindows
          ? null
          : (reading.unavailableReason ??
              'No usage is available for ${descriptor.displayName}.'),
      usageUnavailableIsPermanent: reading.isPermanent,
    );
  }

  Future<ProviderConnection> _update(ProviderConnection next) async {
    _connection = next;
    if (next.status != ConnectionStatus.connecting) {
      await _connections.save(next);
    }
    return next;
  }

  @override
  Future<void> dispose() async {}
}
