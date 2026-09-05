import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import '../models/app_settings.dart';
import '../models/rail_placement.dart';
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

  /// Connecting one app.
  connectProvider,

  /// Preferences.
  settings,

  /// One provider, in detail.
  providerDetail,

  /// Choosing which provider fills an empty rail position.
  slotPicker,

  /// First run, before the widget has ever been shown.
  onboarding;

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
  }) : _native = native,
       _settingsService = settingsService,
       _usage = usageController,
       _log = logger ?? const Logger('shell') {
    _native
      ..onExpansionChanged = _handleExpansionChanged
      ..onModeChanged = _handleModeChanged
      ..onRefreshRequested = _handleRefreshRequested
      ..onRailToggleRequested = hideRailFromMenu
      ..onRailRevealRequested = revealRail
      ..onMetricsChanged = reloadMetrics
      // Braced deliberately: an arrow body would swallow the following
      // cascade into the closure.
      ..onSettingsRequested = () {
        unawaited(openPanel(ShellSurface.settings));
      };

    _settingsService.addListener(_handleSettingsChanged);
  }

  /// Size of the window in each panel surface. The rail's size is fixed by
  /// [RailMetrics] and set natively.
  static const Size connectSize = Size(460, 520);
  // Wider than a single-column sheet: the sidebar takes ~150pt before the page
  // starts, and squeezing both into 640 left the settings rows wrapping.
  static const Size settingsSize = Size(760, 600);
  static const Size detailSize = Size(520, 560);
  static const Size slotPickerSize = Size(460, 460);

  /// Taller than it is wide. The first-run pages are a name, a sentence and a
  /// button — laid out at the width of the settings panel they would be a
  /// short line of text stranded in a lot of empty space.
  static const Size onboardingSize = Size(440, 660);

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
  int? _slotIndex;

  /// Which provider the detail surface is about.
  String? get detailProviderId => _detailProviderId;

  /// Which rail position the picker is filling. Null outside that surface.
  int? get slotIndex => _slotIndex;

  List<NativeScreen> _screens = const [];
  List<NativeScreen> get screens => _screens;

  AppSettings _lastAppliedPlacement = const AppSettings();

  // MARK: - Startup

  /// Reads native geometry, then shows whichever surface the user should see.
  Future<void> start() async {
    await _readMetrics();
    _screens = await _native.listScreens();
    notifyListeners();

    await _applyPlacement(force: true);

    if (!_settings.onboardingComplete) {
      await openPanel(ShellSurface.onboarding);
      return;
    }

    await showRail();
  }

  // MARK: - Surfaces

  /// Switches the window to the rail.
  Future<void> showRail() async {
    _surface = ShellSurface.rail;
    _detailProviderId = null;
    _slotIndex = null;
    notifyListeners();

    await _native.hidePanel();
    if (_settings.railVisible) {
      await _native.showRail(
        pinnedOpen: !_settings.railExpansion.autoCollapses,
      );
    }
  }

  /// Opens a centred, focusable surface.
  Future<void> openPanel(
    ShellSurface next, {
    String? providerId,
    int? slotIndex,
  }) async {
    assert(next.isPanel, 'openPanel is for panel surfaces only');

    _surface = next;
    _detailProviderId = providerId;
    _slotIndex = slotIndex;
    notifyListeners();

    await _native.showPanel(size: _sizeFor(next));
  }

  static Size _sizeFor(ShellSurface surface) => switch (surface) {
    ShellSurface.connectProvider => connectSize,
    ShellSurface.settings => settingsSize,
    ShellSurface.providerDetail => detailSize,
    ShellSurface.slotPicker => slotPickerSize,
    ShellSurface.onboarding => onboardingSize,
    ShellSurface.rail => connectSize,
  };

  // MARK: - Rail behaviour

  Future<void> toggleRailVisibility() async {
    final next = !_settings.railVisible;
    await _settingsService.update(_settings.copyWith(railVisible: next));

    if (_surface != ShellSurface.rail) {
      await showRail();
      return;
    }
    next
        ? await _native.showRail(
            pinnedOpen: !_settings.railExpansion.autoCollapses,
          )
        : await _native.hideRail();
  }

  /// Re-reads the rail's measurements from the native side.
  ///
  /// Called when the rail moves to a display of a different size. Without it
  /// the window resizes and the rings keep the size they had, which is worse
  /// than either scale on its own.
  Future<void> reloadMetrics() async {
    await _readMetrics();
    notifyListeners();
  }

  /// Reads the measurements, keeping the ones already held if the read fails.
  ///
  /// A failed call answers with [RailMetrics.fallback], which is drawn for a
  /// 1080-point display at scale one. Replacing real measurements with it
  /// puts small rings and a misplaced settings control inside a window that
  /// is still the right size — which is what was seen, briefly, when a read
  /// happened to fail. Better to keep what was true a moment ago.
  Future<void> _readMetrics() async {
    final fresh = await _native.railMetrics();
    final failed = identical(fresh, RailMetrics.fallback);
    final haveReal = !identical(_metrics, RailMetrics.fallback);
    if (failed && haveReal) return;
    _metrics = fresh;
  }

  /// Puts this Mac back to how it was before DevNotch was ever run.
  ///
  /// Clears the stored settings, connections and history, drops what is held
  /// in memory, and returns to the intro screen — the same sequence a genuine
  /// first launch goes through. See [SettingsService.resetEverything] for why
  /// deleting the app is not enough on its own.
  Future<void> resetEverything() async {
    await _usage.forgetEverything();
    await _settingsService.resetEverything();
    _lastAppliedPlacement = const AppSettings();
    await _applyPlacement(force: true);
    await openPanel(ShellSurface.onboarding);
  }

  /// Takes the rail off screen, because the user chose "Hide Rail".
  ///
  /// Distinct from [toggleRailVisibility]: a menu item that says Hide must
  /// hide. Toggling behind that label is how a second click on what looked
  /// like the same action brought the rail back and made the state
  /// unpredictable.
  Future<void> hideRailFromMenu() async {
    if (_settings.railVisible) {
      await _settingsService.update(_settings.copyWith(railVisible: false));
    }
    if (_surface == ShellSurface.rail) await _native.hideRail();
  }

  /// Brings the rail back and opens it.
  ///
  /// What the menu-bar icon does. It only ever reveals: clicking the icon used
  /// to run [toggleRailVisibility], which switched the rail off and wrote that
  /// to preferences, so the widget disappeared and did not come back until the
  /// user worked out that the icon they had just clicked was the way to undo
  /// it. Hiding stays available, on the context menu, where it is labelled.
  Future<void> revealRail() async {
    if (!_settings.railVisible) {
      await _settingsService.update(_settings.copyWith(railVisible: true));
    }
    if (_surface != ShellSurface.rail) {
      await showRail();
    } else {
      await _native.showRail(
        pinnedOpen: !_settings.railExpansion.autoCollapses,
      );
    }
    await _native.expandRail();
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
    final changed =
        force ||
        s.railAppearance != _lastAppliedPlacement.railAppearance ||
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
    await _native.setRailGlass(s.railAppearance == RailAppearance.glass);

    if (_surface == ShellSurface.rail) {
      s.railVisible
          ? await _native.showRail(pinnedOpen: !s.railExpansion.autoCollapses)
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
