import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../models/app_settings.dart';
import 'native/native_bridge.dart';
import 'settings_service.dart';
import 'usage_controller.dart';

/// Which surface the app's single window is currently showing.
///
/// Flutter owns one view, so the app owns one window and changes what it is
/// rather than opening more. This enum is the Dart half of that decision; the
/// Swift half is `RailMode`.
enum ShellSurface {
  /// The edge widget. The product's primary interface.
  rail,

  /// First-run "Connect your AI tools".
  onboarding,

  /// Preferences.
  settings,

  /// One provider, in detail.
  providerDetail;

  /// True for surfaces that need a centred, focusable window.
  bool get isPanel => this != ShellSurface.rail;
}

/// Owns window mode, rail expansion, and which surface is on screen.
///
/// Everything that decides *where the window is and what it is for* lives here,
/// so widgets can be about layout and nothing else.
class ShellController extends ChangeNotifier {
  ShellController({
    required NativeBridge native,
    required SettingsService settingsService,
    required UsageController usageController,
    Logger? logger,
  })  : _native = native,
        _settingsService = settingsService,
        _usage = usageController,
        _log = logger ?? const Logger('shell') {
    _native
      ..onExpansionChanged = _handleExpansionChanged
      ..onModeChanged = _handleModeChanged
      ..onRefreshRequested = _handleRefreshRequested
      ..onRailToggleRequested = toggleRailVisibility
      // Braced deliberately: an arrow body would swallow the following
      // cascade into the closure.
      ..onSettingsRequested = () {
        unawaited(openPanel(ShellSurface.settings));
      };

    _settingsService.addListener(_handleSettingsChanged);
  }

  /// Size of the window in each panel surface. The rail's size is fixed by
  /// [RailMetrics] and set natively.
  static const Size onboardingSize = Size(760, 600);
  static const Size settingsSize = Size(640, 580);
  static const Size detailSize = Size(520, 560);

  final NativeBridge _native;
  final SettingsService _settingsService;
  final UsageController _usage;
  final Logger _log;

  AppSettings get _settings => _settingsService.settings;

  RailMetrics _metrics = RailMetrics.fallback;
  RailMetrics get metrics => _metrics;

  ShellSurface _surface = ShellSurface.rail;
  ShellSurface get surface => _surface;

  bool _isExpanded = false;

  /// True when the rail is showing its full panel. Always true while the
  /// user has asked for it to stay open.
  bool get isExpanded =>
      _isExpanded || _settings.railExpansion.autoCollapses == false;

  String? _detailProviderId;

  /// Which provider the detail surface is about.
  String? get detailProviderId => _detailProviderId;

  List<NativeScreen> _screens = const [];
  List<NativeScreen> get screens => _screens;

  AppSettings _lastAppliedPlacement = const AppSettings();

  // MARK: - Startup

  /// Reads native geometry, then shows whichever surface the user should see.
  Future<void> start() async {
    _metrics = await _native.railMetrics();
    _screens = await _native.listScreens();
    notifyListeners();

    await _applyPlacement(force: true);

    if (_settings.onboardingComplete || _usage.hasAnyConnection) {
      await showRail();
    } else {
      await openPanel(ShellSurface.onboarding);
    }
  }

  // MARK: - Surfaces

  /// Switches the window to the rail.
  Future<void> showRail() async {
    _surface = ShellSurface.rail;
    _detailProviderId = null;
    notifyListeners();

    await _native.hidePanel();
    if (_settings.railVisible) {
      await _native.showRail(
        pinnedOpen: !_settings.railExpansion.autoCollapses,
      );
    }
  }

  /// Opens a centred, focusable surface.
  Future<void> openPanel(ShellSurface next, {String? providerId}) async {
    assert(next.isPanel, 'openPanel is for panel surfaces only');

    _surface = next;
    _detailProviderId = providerId;
    notifyListeners();

    await _native.showPanel(size: _sizeFor(next));
  }

  /// Leaves a panel surface for the rail, marking onboarding done on the way
  /// out so the connect screen is not shown again.
  Future<void> finishOnboarding() async {
    if (!_settings.onboardingComplete) {
      await _settingsService.update(
        _settings.copyWith(onboardingComplete: true),
      );
    }
    await showRail();
  }

  static Size _sizeFor(ShellSurface surface) => switch (surface) {
        ShellSurface.onboarding => onboardingSize,
        ShellSurface.settings => settingsSize,
        ShellSurface.providerDetail => detailSize,
        ShellSurface.rail => onboardingSize,
      };

  // MARK: - Rail behaviour

  Future<void> toggleRailVisibility() async {
    final next = !_settings.railVisible;
    await _settingsService.update(_settings.copyWith(railVisible: next));

    if (_surface != ShellSurface.rail) {
      await showRail();
      return;
    }
    next ? await _native.showRail(pinnedOpen: !_settings.railExpansion.autoCollapses)
        : await _native.hideRail();
  }

  /// Opens the rail from a click, for users who turned hover-expansion off.
  Future<void> expandRail() => _native.expandRail();

  void _handleExpansionChanged(bool expanded) {
    if (_isExpanded == expanded) return;
    _isExpanded = expanded;
    notifyListeners();

    // Opening the rail is the moment its numbers are looked at, so it is also
    // the moment they are worth re-checking — but only if they are stale
    // enough to be worth a request.
    if (expanded) _refreshIfStale();
  }

  void _handleModeChanged(String mode) {
    _log.debug('window mode changed to $mode');
  }

  void _handleRefreshRequested() {
    unawaited(_usage.refreshAll());
  }

  void _refreshIfStale() {
    final last = _usage.lastUpdated;
    if (last == null) return;
    if (DateTime.now().difference(last) < const Duration(seconds: 30)) return;
    unawaited(_usage.refreshAll());
  }

  // MARK: - Placement

  void _handleSettingsChanged() {
    unawaited(_applyPlacement());
    notifyListeners();
  }

  /// Pushes edge, offset, and monitor down to the window.
  ///
  /// Skipped when nothing that affects placement changed, so unrelated
  /// preference edits do not make the rail jump.
  Future<void> _applyPlacement({bool force = false}) async {
    final s = _settings;
    final changed = force ||
        s.railEdge != _lastAppliedPlacement.railEdge ||
        s.railOffset != _lastAppliedPlacement.railOffset ||
        s.screenId != _lastAppliedPlacement.screenId ||
        s.railExpansion != _lastAppliedPlacement.railExpansion ||
        s.railVisible != _lastAppliedPlacement.railVisible;

    _lastAppliedPlacement = s;
    if (!changed) return;

    await _native.configureRail(
      edge: s.railEdge,
      offset: s.railOffset.clamped(),
      screenId: s.screenId,
    );
    await _native.setRailPinnedOpen(!s.railExpansion.autoCollapses);

    if (_surface == ShellSurface.rail) {
      s.railVisible
          ? await _native.showRail(
              pinnedOpen: !s.railExpansion.autoCollapses,
            )
          : await _native.hideRail();
    }
  }

  /// Re-reads the display list, for the monitor picker in Settings.
  Future<void> reloadScreens() async {
    _screens = await _native.listScreens();
    notifyListeners();
  }

  @override
  void dispose() {
    _settingsService.removeListener(_handleSettingsChanged);
    super.dispose();
  }
}
