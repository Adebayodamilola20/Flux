import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
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

  String get id => descriptor.id;
  String get displayName => descriptor.displayName;

  /// True before any result of any kind has arrived.
  bool get isInitialLoad => data == null && failure == null;

  /// Percentage for the rail's ring, or null when nothing is measurable.
  ///
  /// Null is rendered as a dash. It is never substituted with zero, which the
  /// user would read as "I have used nothing".
  int? get percent => data?.primaryPercent;

  ActivityStatus get activity => data?.activity ?? ActivityStatus.unknown;

  /// What the rail should say about this slot right now.
  ConnectionStatus get status {
    if (connection.status == ConnectionStatus.unsupported) {
      return ConnectionStatus.unsupported;
    }
    if (isRefreshing && data == null) return ConnectionStatus.connecting;
    if (failure != null) return ConnectionStatus.error;
    return data?.connection ?? connection.status;
  }

  /// True when this slot has been connected and should appear in the rail with
  /// live figures rather than an invitation to connect.
  bool get isLive => data != null;

  ProviderState copyWith({
    ProviderConnection? connection,
    UsageData? data,
    UsageFailure? failure,
    bool clearFailure = false,
    bool? isRefreshing,
    DateTime? lastUpdated,
  }) {
    return ProviderState(
      descriptor: descriptor,
      connection: connection ?? this.connection,
      data: data ?? this.data,
      failure: clearFailure ? null : (failure ?? this.failure),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastUpdated: lastUpdated ?? this.lastUpdated,
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
  bool _disposed = false;

  AppSettings get _settings => _settingsService.settings;

  /// Slot states in rail order.
  List<ProviderState> get states => [
    for (final p in _registry.all) _states[p.id]!,
  ];

  ProviderState stateFor(String providerId) => _states[providerId]!;

  /// The slot that drives the menu-bar fallback: the first one with a figure,
  /// else the first slot.
  ProviderState get primary {
    for (final state in states) {
      if (state.percent != null) return state;
    }
    return states.first;
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

    _scheduleTimer();
    await refreshAll();
  }

  /// Fetches every connected slot.
  Future<void> refreshAll() async {
    await Future.wait([
      for (final provider in _registry.all)
        if (provider.connection.isConnected) refresh(provider.id),
    ]);
  }

  /// Fetches one slot. Concurrent calls for the same slot collapse into the
  /// in-flight one.
  Future<void> refresh(String providerId) async {
    final provider = _registry.byId(providerId);
    if (provider == null) return;

    final state = _states[providerId]!;
    if (state.isRefreshing) return;

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
      _states[providerId] = _states[providerId]!.copyWith(isRefreshing: false);
      _safeNotify();
      await _syncMenuBar();
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

  /// Pushes the summary to the native status item.
  Future<void> _syncMenuBar() async {
    if (_disposed) return;
    final state = primary;
    await _native.updateMenuBar(
      showIcon: _settings.effectiveShowMenuBarIcon,
      showPercent: _settings.showMenuBarPercent,
      percent: state.percent,
      isError: state.failure != null,
    );
  }

  void _onSettingsChanged() {
    _scheduleTimer();
    unawaited(_syncMenuBar());
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_settings.refreshInterval, (_) => refreshAll());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _settingsService.removeListener(_onSettingsChanged);
    unawaited(_registry.disposeAll());
    super.dispose();
  }
}
