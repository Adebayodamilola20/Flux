import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../models/active_session.dart';
import '../models/app_settings.dart';
import '../models/connection_status.dart';
import '../models/provider_connection.dart';
import '../models/usage_data.dart';
import '../models/usage_failure.dart';
import '../providers/provider_registry.dart';
import '../providers/usage_provider.dart';
import 'history_service.dart';
import 'native/native_bridge.dart';
import 'settings_service.dart';

/// Everything the UI knows about one provider slot.
///
/// A slot always has a state, even before its first fetch and even when it has
/// no implementation, so the rail can draw three rows from the moment it opens
/// without any of them being a special case.
@immutable
class ProviderState {
  const ProviderState({
    required this.descriptor,
    required this.connection,
    this.data,
    this.failure,
    this.isRefreshing = false,
    this.lastUpdated,
    this.sessions = const [],
  });

  final ProviderDescriptor descriptor;
  final ProviderConnection connection;

  /// The last successful snapshot. Retained through a later failure so the UI
  /// can show the previous figure alongside "last updated", rather than
  /// blanking out.
  final UsageData? data;

  /// The most recent failure, cleared by the next success.
  final UsageFailure? failure;

  final bool isRefreshing;
  final DateTime? lastUpdated;

  /// Tools of this provider's running on this Mac right now.
  ///
  /// Kept outside [data] because it is observed without any account link and
  /// must survive a provider that is not connected, has no usage, or failed
  /// its last fetch.
  final List<ActiveSession> sessions;

  String get id => descriptor.id;
  String get displayName => descriptor.displayName;

  /// True before any result of any kind has arrived.
  bool get isInitialLoad => data == null && failure == null;

  /// Percentage for the rail's ring, or null when nothing is measurable.
  ///
  /// Null is rendered as a dash. It is never substituted with zero, which the
  /// user would read as "I have used nothing".
  int? get percent => data?.primaryPercent;

  ActivityStatus get activity {
    if (descriptor.isImplemented == false) return ActivityStatus.unknown;
    if (sessions.isEmpty) return ActivityStatus.idle;
    return sessions.any((s) => s.isBusy)
        ? ActivityStatus.working
        : ActivityStatus.waiting;
  }

  /// What the rail should say about this slot right now.
  ///
  /// Account state and usage availability are separate questions. A connected
  /// account whose quota could not be read is still **connected** — the user
  /// signed in successfully and has nothing to fix — so only an authentication
  /// failure is allowed to downgrade it. Reporting "Disconnected" because a
  /// provider has no quota endpoint would send the user to re-authorise
  /// something that was never broken.
  ConnectionStatus get status {
    if (connection.status == ConnectionStatus.unsupported) {
      return ConnectionStatus.unsupported;
    }
    if (isRefreshing && data == null) return ConnectionStatus.connecting;

    final kind = failure?.kind;
    if (kind == UsageFailureKind.authentication) return ConnectionStatus.error;

    if (connection.isConnected) {
      return data?.connection ?? connection.status;
    }
    return failure != null ? ConnectionStatus.error : connection.status;
  }

  /// True when the account is linked but there is no quota to show.
  bool get isUsageUnavailable {
    if (!connection.isConnected) return false;
    if (data?.isUsageUnavailable ?? false) return true;

    // A non-auth failure against a connected account is also "no usage to
    // show" rather than "your account is broken".
    final kind = failure?.kind;
    return kind != null && kind != UsageFailureKind.authentication;
  }

  /// Why usage is missing, when it is.
  String? get usageUnavailableReason =>
      data?.usageUnavailableReason ?? failure?.message;

  /// Whether trying again could plausibly change the answer.
  ///
  /// False when the provider simply publishes no such data — pressing Retry
  /// against an endpoint that does not exist produces the same result every
  /// time, which is how a button becomes noise.
  bool get canRetryUsage {
    if (data?.usageUnavailableIsPermanent ?? false) return false;
    final f = failure;
    if (f != null) return f.isRetryable;
    return true;
  }

  /// True when this slot has been connected and should appear in the rail with
  /// live figures rather than an invitation to connect.
  bool get isLive => data != null;

  /// True when the figure on screen is not one this app could confirm just now.
  ///
  /// Either a fetch is in flight over an existing figure, or the last one
  /// failed for a reason that will be retried — a dropped request, a rate
  /// limit, a CLI that did not answer. In both cases what is displayed is the
  /// *previous* reading, and the user has no way to tell that apart from a
  /// current one unless the rail says so. That is the case where the rail read
  /// 26% while Claude's own menu bar read 31%.
  bool get isReaching {
    if (!connection.isConnected) return false;

    // A figure the provider measured a while ago is the commonest way the
    // rail ends up disagreeing with the tool it reports on — Antigravity's
    // panel is only read when the user asks, and OpenAI reports the Codex
    // allowance only in the reply to a prompt, so both can be hours old. The
    // number is still the best available, but it is not a current reading and
    // must not be presented as one.
    if (data?.windows.any((w) => w.isStale) ?? false) return true;

    return isRetrying;
  }

  /// True when the last attempt failed for a reason that will be retried.
  ///
  /// Narrower than [isReaching], and the difference matters in the card: a
  /// figure that is merely old still has a number worth reading, so the row
  /// keeps showing it and says how old it is. A figure the app could not
  /// fetch has nothing behind it, so the row says it is trying instead.
  bool get isRetrying {
    if (!connection.isConnected) return false;

    // Deliberately not "a fetch is in flight". Polling every thirty seconds
    // means that is true for a moment on every tick, and a spinner that
    // flickers twice a minute on a healthy provider teaches the user to
    // ignore it — which would cost exactly the case it exists for.
    final kind = failure?.kind;
    if (kind == null) return false;
    // An authentication problem is not something to keep spinning about: the
    // user has to go and fix it, and a hopeful indicator would say otherwise.
    return kind != UsageFailureKind.authentication;
  }

  ProviderState copyWith({
    ProviderConnection? connection,
    UsageData? data,
    UsageFailure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    DateTime? lastUpdated,
    List<ActiveSession>? sessions,
  }) {
    return ProviderState(
      descriptor: descriptor,
      connection: connection ?? this.connection,
      data: data ?? this.data,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      sessions: sessions ?? this.sessions,
    );
  }
}

/// Owns the usage lifecycle for every provider slot: scheduling refreshes,
/// exposing loading and error states, recording history, running connect and
/// disconnect flows, and pushing the summary to the menu-bar fallback.
///
/// Provider-agnostic — it talks to [UsageProvider] and never to Claude
/// directly.
class UsageController extends ChangeNotifier {
  UsageController({
    required ProviderRegistry registry,
    required SettingsService settingsService,
    required HistoryService historyService,
    required NativeBridge native,
    Logger? logger,
  }) : _registry = registry,
       _settingsService = settingsService,
       _history = historyService,
       _native = native,
       _log = logger ?? const Logger('usage') {
    _states = {
      for (final provider in registry.all)
        provider.id: ProviderState(
          descriptor: provider.descriptor,
          connection: provider.connection,
        ),
    };
    _settingsService.addListener(_onSettingsChanged);
  }

  final ProviderRegistry _registry;
  final SettingsService _settingsService;
  final HistoryService _history;
  final NativeBridge _native;
  final Logger _log;

  late Map<String, ProviderState> _states;
  Timer? _timer;

  /// Extra timers for providers that want polling faster than the user's
  /// interval. Keyed by provider id so rescheduling replaces cleanly.
  final Map<String, Timer> _fastTimers = {};

  /// Collapses bursts of change events into one refresh.
  ///
  /// A provider's tool can rewrite its state file several times in a second —
  /// once per streamed response, say. Without this, each write would start its
  /// own fetch and the rail would spend more time refreshing than showing a
  /// number.
  final Map<String, Timer> _debounces = {};

  /// How long to wait for a change burst to settle. Short enough to feel
  /// immediate, long enough that a multi-write update fetches once.
  static const Duration changeDebounce = Duration(milliseconds: 400);

  /// The least time a manual refresh shows as in progress, so a press that is
  /// answered instantly still visibly does something.
  static const Duration manualRefreshHold = Duration(milliseconds: 650);

  /// Providers whose Refresh was pressed while a fetch was already running.
  final Set<String> _manualQueued = {};

  final List<StreamSubscription<void>> _watchers = [];
  bool _disposed = false;

  AppSettings get _settings => _settingsService.settings;

  /// Every provider's state, in catalog order.
  ///
  /// What the *rail* shows is [slots]; this is the full set, used by the
  /// settings screen and by anything that needs a provider regardless of
  /// whether the user has put it on the rail.
  List<ProviderState> get states => [
    for (final p in _registry.all) _states[p.id]!,
  ];

  /// What each rail position holds, or null where it holds nothing.
  ///
  /// The rail is positional and the assignment is the user's: any provider can
  /// sit in any slot, and an empty entry draws a plus. Derived from settings
  /// rather than from registry order, so adding a provider to the build does
  /// not silently push itself onto anyone's rail.
  List<ProviderState?> get slots => [
    for (final id in _settings.slots) id == null ? null : _states[id],
  ];

  /// Providers not currently on the rail — what the picker offers.
  List<ProviderState> get unassigned => [
    for (final p in _registry.all)
      if (!_settings.hasSlotFor(p.id) && p.descriptor.isImplemented)
        _states[p.id]!,
  ];

  /// Which rail position holds [providerId], or null when it is not on the
  /// rail at all.
  int? slotIndexOf(String providerId) => _settings.slotIndexOf(providerId);

  /// Puts [providerId] in slot [index] and connects it.
  ///
  /// Adding is the only click: these providers read a tool that is already
  /// signed in on this Mac, so a separate Connect step would ask the user to
  /// confirm something the app can simply do.
  Future<void> assignSlot(
    int index,
    String providerId, {
    bool connect = true,
  }) async {
    if (index < 0 || index >= _settings.slots.length) return;

    final next = [..._settings.slots];
    // A provider can only be in one place; moving it empties where it was.
    final existing = next.indexOf(providerId);
    if (existing != -1) next[existing] = null;
    next[index] = providerId;

    await _settingsService.update(_settings.copyWith(slots: next));
    _safeNotify();

    if (!connect) return;

    final provider = _registry.byId(providerId);
    if (provider == null) return;

    if (!provider.connection.isConnected) {
      final result = await provider.enableLocalOnly();
      _applyConnection(providerId, result);
    }
    await refresh(providerId);
  }

  /// Connects a provider from its own connect screen.
  ///
  /// The same work [assignSlot] does when adding, exposed on its own for the
  /// screen that asks first — a provider already on the rail but switched off,
  /// or one the user wants to see the result for before committing.
  Future<void> connectLocally(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) return;

    final result = await provider.enableLocalOnly();
    _applyConnection(providerId, result);
    if (result.isConnected) await refresh(providerId);
  }

  /// Empties slot [index].
  ///
  /// Takes the provider off the rail without disconnecting it: "I do not want
  /// this on screen" and "forget my account" are different requests, and the
  /// second one has its own button.
  Future<void> clearSlot(int index) async {
    if (index < 0 || index >= _settings.slots.length) return;

    final next = [..._settings.slots];
    next[index] = null;
    await _settingsService.update(_settings.copyWith(slots: next));
    _safeNotify();
  }

  ProviderState stateFor(String providerId) => _states[providerId]!;

  /// What drives the menu-bar fallback: the first slot with a figure.
  ///
  /// Null when the rail is empty, which is the starting state — the menu bar
  /// then shows the icon alone rather than a percentage for something the user
  /// has not added.
  ProviderState? get primary {
    for (final state in slots) {
      if (state?.percent != null) return state;
    }
    for (final state in slots) {
      if (state != null) return state;
    }
    return null;
  }

  /// True while any slot is fetching.
  bool get isRefreshing => _states.values.any((s) => s.isRefreshing);

  /// True when any provider has something running on this machine right now.
  ///
  /// The resting sliver is tinted from this — it is the one thing worth
  /// signalling at a size too small to read.
  bool get hasActivity =>
      _states.values.any((s) => s.activity == ActivityStatus.working);

  /// True when no slot has been connected yet, which is what sends the user to
  /// the connect screen on first launch.
  bool get hasAnyConnection =>
      _states.values.any((s) => s.connection.isConnected);

  /// True when the user has put nothing on the rail yet.
  bool get hasEmptyRail => _settings.slots.every((id) => id == null);

  DateTime? get lastUpdated {
    DateTime? newest;
    for (final state in _states.values) {
      final t = state.lastUpdated;
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return newest;
  }

  // MARK: - Lifecycle

  /// Loads stored connections and performs the first fetch.
  Future<void> start() async {
    await _registry.restoreAll();
    for (final provider in _registry.all) {
      _states[provider.id] = _states[provider.id]!.copyWith(
        connection: provider.connection,
      );
    }
    _safeNotify();

    _watchProviders();
    _scheduleTimer();
    await refreshAll();
  }

  /// Subscribes to providers that can tell us when their data changed.
  ///
  /// A timer alone means a figure can sit up to one refresh interval out of
  /// date; this closes that gap for the providers that can signal.
  void _watchProviders() {
    for (final provider in _registry.all) {
      final changes = provider.changes;
      if (changes == null) continue;
      _watchers.add(
        changes.listen(
          (_) => _onProviderChanged(provider),
          onError: (Object e) =>
              _log.debug('watch failed for ${provider.id}: ${e.runtimeType}'),
        ),
      );
    }
  }

  /// Re-fetches a provider whose underlying data just changed.
  ///
  /// Debounced, and deliberately not gated on the refresh timer: the whole
  /// point of a change signal is that it beats the next scheduled poll.
  void _onProviderChanged(UsageProvider provider) {
    if (_disposed) return;
    if (!provider.connection.isConnected) return;

    _debounces[provider.id]?.cancel();
    _debounces[provider.id] = Timer(changeDebounce, () {
      _debounces.remove(provider.id);
      if (_disposed) return;
      unawaited(refresh(provider.id));
    });
  }

  /// Fetches every connected slot, and observes local activity for all of them.
  ///
  /// Activity is not gated on being connected: a Claude Code session running on
  /// this Mac is worth showing whether or not the user has linked an account,
  /// and for providers with no account sign-in at all it is the only thing
  /// there is to show.
  Future<void> refreshAll() async {
    await Future.wait([
      refreshActivity(),
      for (final provider in _registry.all)
        if (provider.connection.isConnected) refresh(provider.id),
    ]);
  }

  /// Re-scans for locally running tools across every slot.
  Future<void> refreshActivity() async {
    await Future.wait([
      for (final provider in _registry.all) _detect(provider),
    ]);
    _safeNotify();
  }

  Future<void> _detect(UsageProvider provider) async {
    try {
      final sessions = await provider.detectActivity();
      _states[provider.id] = _states[provider.id]!.copyWith(sessions: sessions);
    } catch (e) {
      // Activity is a nicety; failing to observe it must never break a refresh.
      _log.debug('activity scan failed for ${provider.id}: ${e.runtimeType}');
    }
  }

  /// Fetches one slot. Concurrent calls for the same slot collapse into the
  /// in-flight one.
  ///
  /// [manual] marks a refresh the user asked for, which lets a provider drop
  /// caches a scheduled poll would rightly keep — the difference between "check
  /// again on the timer" and "I have just fixed the thing you complained about,
  /// try now".
  Future<void> refresh(String providerId, {bool manual = false}) async {
    final provider = _registry.byId(providerId);
    if (provider == null) return;

    final state = _states[providerId]!;
    if (state.isRefreshing) {
      // A press that arrives while a poll is running must not be dropped: the
      // poll may be serving a cache the user is pressing precisely to bypass.
      // It runs again as soon as this one finishes.
      if (manual) _manualQueued.add(providerId);
      return;
    }

    if (manual) provider.invalidateCaches();

    final startedAt = DateTime.now();
    _states[providerId] = state.copyWith(isRefreshing: true);
    _safeNotify();

    try {
      final result = await provider.fetchUsage(_settings);
      _states[providerId] = _states[providerId]!.copyWith(
        data: result,
        clearFailure: true,
        lastUpdated: result.fetchedAt,
        connection: provider.connection,
      );

      if (_settings.recordHistory) {
        await _history.record(result);
      }
      _log.debug('$providerId refreshed: ${result.windows.length} windows');
    } on UsageFailure catch (e) {
      _states[providerId] = _states[providerId]!.copyWith(failure: e);
      _log.warn('$providerId refresh failed: ${e.kind.name}');
    } catch (e, stack) {
      _states[providerId] = _states[providerId]!.copyWith(
        failure: const UsageFailure(
          UsageFailureKind.unknown,
          'Usage could not be retrieved.',
        ),
      );
      _log.error(
        'unexpected refresh error for $providerId',
        e.runtimeType,
        stack,
      );
    } finally {
      // A manual refresh that answers from cache is over in a frame, which
      // reads as the button having done nothing. Show the working state for
      // long enough to be seen; the figure itself is already updated above.
      if (manual) {
        final remaining =
            manualRefreshHold - DateTime.now().difference(startedAt);
        if (remaining > Duration.zero) {
          _safeNotify();
          await Future<void>.delayed(remaining);
        }
      }
      _states[providerId] = _states[providerId]!.copyWith(isRefreshing: false);
      _safeNotify();
      await _syncMenuBar();

      if (_manualQueued.remove(providerId) && !_disposed) {
        unawaited(refresh(providerId, manual: true));
      }
    }
  }

  // MARK: - Connection

  /// Starts a provider's authentication flow.
  ///
  /// The provider decides what that means; this method only records the
  /// resulting state and refreshes if the flow completed immediately.
  Future<ProviderConnection> connect(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) {
      return ProviderConnection.notConnected(providerId);
    }

    final result = await provider.connect(launchUrl: _native.openUrl);
    _applyConnection(providerId, result);

    if (result.isConnected) await refresh(providerId);
    return result;
  }

  /// Finishes a flow with whatever the provider asked the user for — a
  /// credential from its console, or a code from a URL-scheme callback.
  Future<ProviderConnection> completeAuthentication(
    String providerId,
    String payload,
  ) async {
    final provider = _registry.byId(providerId);
    if (provider == null) {
      return ProviderConnection.notConnected(providerId);
    }

    _applyConnection(
      providerId,
      provider.connection.copyWith(status: ConnectionStatus.connecting),
    );

    final result = await provider.completeAuthentication(payload);
    _applyConnection(providerId, result);

    if (result.isConnected) await refresh(providerId);
    return result;
  }

  /// Adopts local-only tracking for a provider that supports it.
  Future<ProviderConnection> enableLocalOnly(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) {
      return ProviderConnection.notConnected(providerId);
    }

    final result = await provider.enableLocalOnly();
    _applyConnection(providerId, result);

    if (result.isConnected) await refresh(providerId);
    return result;
  }

  Future<void> disconnect(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) return;

    await provider.disconnect();
    _states[providerId] = ProviderState(
      descriptor: provider.descriptor,
      connection: provider.connection,
    );
    _safeNotify();
    await _syncMenuBar();
  }

  void _applyConnection(String providerId, ProviderConnection connection) {
    _states[providerId] = _states[providerId]!.copyWith(connection: connection);
    _safeNotify();
  }

  // MARK: - Internals

  /// How long each provider holds the menu bar before the next one.
  ///
  /// Long enough to read and not be a distraction in peripheral vision; short
  /// enough that a glance at a three-provider rail sees all of them inside a
  /// quarter of a minute.
  static const Duration menuBarDwell = Duration(seconds: 4);

  Timer? _menuBarCycle;
  int _menuBarIndex = 0;

  /// Everything on the rail that has a figure worth putting in the menu bar.
  ///
  /// The menu bar used to show the first slot alone, which meant Claude
  /// forever: the other two were measured, on the rail, and invisible up
  /// there. Anything the user put on the rail earned its turn.
  List<ProviderState> get menuBarRotation => [
    for (final state in slots)
      if (state != null && (state.percent != null || state.failure != null))
        state,
  ];

  /// Pushes the summary to the native status item.
  Future<void> _syncMenuBar() async {
    if (_disposed) return;

    final rotation = menuBarRotation;
    _scheduleMenuBarCycle(rotation.length);

    // Nothing measurable yet: the icon alone, rather than a percentage for
    // something the user has not added.
    if (rotation.isEmpty) {
      await _native.updateMenuBar(
        showIcon: _settings.effectiveShowMenuBarIcon,
        showPercent: _settings.showMenuBarPercent,
        percent: null,
      );
      return;
    }

    // Providers come and go from the rail while this is running, so the index
    // is wrapped at use rather than trusted to still be in range.
    final state = rotation[_menuBarIndex % rotation.length];

    await _native.updateMenuBar(
      showIcon: _settings.effectiveShowMenuBarIcon,
      showPercent: _settings.showMenuBarPercent,
      percent: state.percent,
      isError: state.failure != null,
      // Only worth naming when there is more than one to tell apart.
      label: rotation.length > 1 ? state.displayName : null,
    );
  }

  /// Runs the changeover timer, and only while it can change anything.
  void _scheduleMenuBarCycle(int count) {
    final wanted = _settings.showMenuBarPercent && count > 1;
    if (!wanted) {
      _menuBarCycle?.cancel();
      _menuBarCycle = null;
      _menuBarIndex = 0;
      return;
    }
    if (_menuBarCycle != null) return;

    _menuBarCycle = Timer.periodic(menuBarDwell, (_) {
      if (_disposed) return;
      _menuBarIndex++;
      unawaited(_syncMenuBar());
    });
  }

  void _onSettingsChanged() {
    _scheduleTimer();
    unawaited(_syncMenuBar());
  }

  /// Rebuilds the polling schedule: one shared timer, plus a faster one for
  /// each provider that asked for it.
  ///
  /// A provider's preference is only honoured when it is *shorter* than the
  /// user's interval. The setting stays a ceiling — a user who chose one hour
  /// still gets hourly polling for everything that does not opt in, and nothing
  /// can use this to poll less often than they asked.
  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_settings.refreshInterval, (_) => refreshAll());

    for (final timer in _fastTimers.values) {
      timer.cancel();
    }
    _fastTimers.clear();

    for (final provider in _registry.all) {
      final preferred = provider.preferredRefreshInterval;
      if (preferred == null || preferred >= _settings.refreshInterval) continue;

      _fastTimers[provider.id] = Timer.periodic(preferred, (_) {
        if (_disposed) return;
        if (!provider.connection.isConnected) return;
        unawaited(refresh(provider.id));
      });
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _menuBarCycle?.cancel();
    for (final timer in [..._fastTimers.values, ..._debounces.values]) {
      timer.cancel();
    }
    _fastTimers.clear();
    _debounces.clear();
    for (final watcher in _watchers) {
      unawaited(watcher.cancel());
    }
    _watchers.clear();
    _settingsService.removeListener(_onSettingsChanged);
    unawaited(_registry.disposeAll());
    super.dispose();
  }
}
