import 'dart:async';
import 'dart:io';

import '../../core/logger.dart';
import '../../models/usage_window.dart';
import '../../services/native/cli_probe.dart';
import '../../services/native/native_bridge.dart';
import 'cli_quota_parser.dart';
import 'terminal_text.dart';

/// Why a CLI's usage panel could not be read.
enum CliQuotaFailure {
  /// The tool is not installed on this Mac.
  notInstalled,

  /// The CLI ran, but nobody is signed in to it.
  signedOut,

  /// The CLI ran and is signed in, but drew no figures we could read — a
  /// renamed command, a reworked panel, or a session that never got that far.
  noPanel,

  /// The CLI could not be started at all.
  launchFailed,
}

/// A reading taken from a CLI's usage panel.
class CliQuotaSourceReading {
  const CliQuotaSourceReading({
    required this.windows,
    required this.observedAt,
    this.planLabel,
    this.accountLabel,
    this.failure,
  });

  const CliQuotaSourceReading.failed(CliQuotaFailure this.failure)
      : windows = const [],
        observedAt = null,
        planLabel = null,
        accountLabel = null;

  final List<UsageWindow> windows;

  /// When the panel was captured. These readings are expensive enough to cache,
  /// so the age is always worth stating.
  final DateTime? observedAt;

  final String? planLabel;
  final String? accountLabel;
  final CliQuotaFailure? failure;

  bool get hasUsage => windows.isNotEmpty;
}

/// Reads a provider's quota out of its own CLI's usage panel.
///
/// **Why this exists.** Some providers publish no usage API of any kind, and
/// cache nothing to disk — the figure lives only in the CLI's memory, fetched
/// on demand and drawn to the terminal. Antigravity is one: `agy` will tell the
/// signed-in user their weekly limit through `/usage`, and there is no other
/// route to it. The alternative to this class is the card that prompted the
/// work: an account shown as connected, reporting nothing.
///
/// **What it costs, and why it is cached.** Reading the panel means starting
/// the real CLI under a pseudo-terminal, waiting for it to sign in and draw,
/// typing the command, and reading what appeared. That takes the better part of
/// half a minute and starts a real process, so it must not run on the refresh
/// timer. Results are cached for [ttl] and only one probe runs at a time.
///
/// **What it is not.** No credential is read, sent, or stored: the CLI signs
/// itself in exactly as it would for a user at a terminal. Nothing is typed
/// except the usage command itself, and figures are labelled
/// `UsageSource.interactiveCli` so the UI can present them as weaker than an
/// API reading — because a rendered panel is not a contract, and a layout
/// change can make it unreadable.
class CliQuotaSource {
  CliQuotaSource({
    required NativeBridge native,
    required this.executable,
    required this.usageCommand,
    this.ttl = const Duration(minutes: 10),
    Logger? logger,
  })  : _native = native,
        _log = logger ?? Logger('cli.$executable');

  /// The CLI to drive. Must be one the native layer allows.
  final String executable;

  /// The slash command that draws the usage panel, e.g. `/usage`.
  final String usageCommand;

  /// How long a reading stays good. A weekly quota does not move fast enough
  /// to justify paying for a probe more often than this.
  final Duration ttl;

  /// How long a *failed* probe is remembered.
  ///
  /// Shorter than [ttl], because a failure is usually something the user is
  /// about to fix — signing in to the CLI, or installing it. Long enough that a
  /// CLI which cannot produce a panel is not started again on every refresh,
  /// which is a half-minute process launch each time for no result.
  static const Duration failureTtl = Duration(minutes: 3);

  final NativeBridge _native;
  final Logger _log;

  CliQuotaSourceReading? _cached;

  /// The last failure and when it happened, so an unreadable CLI is not driven
  /// again on every poll.
  (CliQuotaFailure, DateTime)? _lastFailure;

  /// In-flight probe, so several refreshes arriving at once wait on one run
  /// rather than starting a CLI each.
  Future<CliQuotaSourceReading>? _inFlight;

  /// True when the CLI is installed on this Mac.
  Future<bool> get isInstalled async =>
      await _native.locateCli(executable) != null;

  /// The last reading, without probing. Null when nothing has been read yet.
  CliQuotaSourceReading? get cached => _cached;

  /// Drops the cached reading and any remembered failure, so the next [read]
  /// drives the CLI again.
  void invalidate() {
    _cached = null;
    _lastFailure = null;
  }

  /// Reads the panel, using the cached reading when it is still fresh.
  ///
  /// [force] skips the cache — what the card's Refresh button asks for.
  ///
  /// [staleIfOlderThan] is when the tool was last seen doing work. A reading
  /// taken before that is known to be out of date whatever the clock says, and
  /// is re-taken. This is what makes a figure move after a session instead of
  /// sitting at its last value until [ttl] happens to expire — the complaint
  /// that "I just used it and it still shows the same number".
  /// Why a reading was not taken because nobody asked for one.
  static const CliQuotaFailure notChecked = CliQuotaFailure.noPanel;

  Future<CliQuotaSourceReading> read({
    bool force = false,
    DateTime? staleIfOlderThan,
    bool allowLaunch = true,
  }) {
    if (!force) {
      final cached = _cached;
      if (cached != null && cached.hasUsage) {
        final at = cached.observedAt;
        final supersededByActivity =
            staleIfOlderThan != null && at != null && at.isBefore(staleIfOlderThan);
        if (at != null &&
            !supersededByActivity &&
            DateTime.now().difference(at) < ttl) {
          return Future.value(cached);
        }
      }

      final failure = _lastFailure;
      if (failure != null &&
          DateTime.now().difference(failure.$2) < failureTtl) {
        return Future.value(CliQuotaSourceReading.failed(failure.$1));
      }
    }

    // Starting the CLI is not a background action.
    //
    // Driving these tools means launching the real thing, and a tool that
    // decides it needs to authenticate opens the provider's sign-in page in
    // the user's browser. On a refresh timer that becomes a browser window
    // appearing out of nowhere, repeatedly, while the user is doing something
    // else — which is what happened. So a launch only ever happens because the
    // user asked: adding the provider, or pressing Refresh. A scheduled poll
    // serves what is already cached and otherwise reports nothing.
    if (!allowLaunch) {
      final cached = _cached;
      if (cached != null && cached.hasUsage) return Future.value(cached);
      return Future.value(const CliQuotaSourceReading.failed(notChecked));
    }

    // A second caller during a probe gets the same run, not a second CLI.
    return _inFlight ??= _probe().whenComplete(() => _inFlight = null);
  }

  /// A small, stable directory to run the CLI in.
  ///
  /// Not the app's own working directory, which is `/` for anything launched
  /// from Finder. These tools treat their working directory as a *workspace* and
  /// index it — pointed at the filesystem root, `agy` spends so long starting
  /// that the usage command never lands, and the probe times out having read
  /// only the startup banner. An empty directory costs nothing to index.
  ///
  /// Stable rather than a fresh temp directory each time, so the CLI's
  /// workspace-trust prompt is answered once instead of on every probe.
  static String? _probeDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null) return null;

    final directory = Directory('$home/.flux/cli-probe');
    try {
      if (!directory.existsSync()) directory.createSync(recursive: true);
    } on FileSystemException {
      return null;
    }
    return directory.path;
  }

  Future<CliQuotaSourceReading> _probe() async {
    final path = await _native.locateCli(executable);
    if (path == null) return _fail(CliQuotaFailure.notInstalled);

    // Timings, from driving the real CLIs. These tools spend several seconds
    // signing themselves in and drawing their first frame, and they put a
    // workspace-trust gate in front of the session that swallows whatever is
    // typed first. So: two early returns (one answers the gate, the other is
    // harmless if it never appeared), then the command well after the prompt is
    // up, then a return to accept the completion menu that typing a slash
    // command opens.
    final result = await _native.probeCli(
      executable: path,
      workingDirectory: _probeDirectory(),
      steps: [
        CliProbeStep.confirm(5),
        CliProbeStep.confirm(9),
        CliProbeStep.command(17, usageCommand),
        CliProbeStep.confirm(20),
      ],
      timeout: const Duration(seconds: 45),
    );

    if (!result.launched) {
      _log.warn('$executable could not be started: ${result.failure}');
      return _fail(CliQuotaFailure.launchFailed);
    }
    if (!result.hasOutput) return _fail(CliQuotaFailure.noPanel);

    final reading = CliQuotaParser.parse(result.output);

    if (reading.isEmpty) {
      final signedOut = _looksSignedOut(result.output);

      _log.info(
        '$executable drew no readable quota '
        '(${signedOut ? 'signed out' : 'no panel'})',
      );
      return _fail(
        signedOut ? CliQuotaFailure.signedOut : CliQuotaFailure.noPanel,
      );
    }

    final fresh = CliQuotaSourceReading(
      windows: reading.windows,
      observedAt: DateTime.now(),
      planLabel: reading.planLabel,
      accountLabel: reading.accountLabel,
    );
    _cached = fresh;
    _lastFailure = null;
    _log.debug('$executable reported ${fresh.windows.length} quota windows');
    return fresh;
  }

  /// Records a failure so the CLI is not driven again immediately.
  CliQuotaSourceReading _fail(CliQuotaFailure failure) {
    _lastFailure = (failure, DateTime.now());
    return CliQuotaSourceReading.failed(failure);
  }

  /// Whether the session really had nobody signed in.
  ///
  /// Deliberately not just a phrase match. `agy` opens with "You are currently
  /// not signed in." and *then* signs itself in from a stored session — so the
  /// phrase alone condemns a session that went on to work, which is exactly how
  /// a probe that merely ran out of time gets reported to the user as "run
  /// `agy` and sign in" when they already are.
  ///
  /// Evidence of a session beats the banner: an account name in the output, or
  /// the plan the CLI prints once it knows it, means the sign-in succeeded and
  /// whatever went wrong afterwards was something else.
  static bool _looksSignedOut(String raw) {
    final text = TerminalText.stripAnsi(raw);

    if (_signedInMarkers.hasMatch(text)) return false;

    final lower = text.toLowerCase();
    return TerminalText.looksSignedOut(raw) ||
        lower.contains('how would you like to authenticate') ||
        lower.contains('sign in with google') ||
        lower.contains('waiting for authentication');
  }

  /// Things a CLI only prints once it knows who it is: an email address, or a
  /// named plan in parentheses.
  static final RegExp _signedInMarkers = RegExp(
    r'[\w.+-]+@[\w-]+\.[\w.-]+|\([^)]*\b(?:quota|plan|tier|subscription)\b[^)]*\)',
    caseSensitive: false,
  );
}
