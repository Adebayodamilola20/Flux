import 'package:flutter/services.dart';

import '../../core/logger.dart';
import 'cli_probe.dart';
import '../../models/rail_placement.dart';

/// Description of a running provider-related process, as reported by the
/// native layer.
class NativeProcessInfo {
  const NativeProcessInfo({
    required this.pid,
    required this.name,
    this.host,
    this.startedAt,
  });

  final int pid;

  /// Executable name (`claude`).
  final String name;

  /// Owning application, resolved from the parent process ("Terminal",
  /// "iTerm2", "Visual Studio Code").
  final String? host;

  final DateTime? startedAt;

  static NativeProcessInfo? fromMap(Object? value) {
    if (value is! Map) return null;
    final pid = value['pid'];
    final name = value['name'];
    if (pid is! int || name is! String) return null;
    final started = value['startedAt'];
    return NativeProcessInfo(
      pid: pid,
      name: name,
      host: value['host'] as String?,
      startedAt: started is num
          ? DateTime.fromMillisecondsSinceEpoch((started * 1000).round())
          : null,
    );
  }
}

/// The result of asking the Keychain for Claude Code's stored session.
///
/// Three outcomes rather than a nullable string, because they call for
/// different behaviour: an absent credential means Claude Code is not signed
/// in, while a refused one means the user said no to a system dialog and the
/// app should quietly use cached figures instead of nagging.
class ClaudeCodeCredentialAccess {
  const ClaudeCodeCredentialAccess.found(String this.blob) : isDenied = false;
  const ClaudeCodeCredentialAccess.absent()
      : blob = null,
        isDenied = false;
  const ClaudeCodeCredentialAccess.denied()
      : blob = null,
        isDenied = true;

  /// The stored credential JSON, or null when there is none to read.
  final String? blob;

  /// True when macOS or the user refused the read.
  final bool isDenied;

  bool get hasBlob => blob != null;
}

/// A display the rail can be placed on.
class NativeScreen {
  const NativeScreen({
    required this.id,
    required this.name,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final bool isPrimary;

  static NativeScreen? fromMap(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || name is! String) return null;
    return NativeScreen(
      id: id,
      name: name,
      isPrimary: value['isPrimary'] as bool? ?? false,
    );
  }
}

/// The rail's geometry, as measured by the native layer.
///
/// These values come from Swift rather than being declared in Dart, because
/// Swift is what positions the window and decides where the pointer counts as
/// being over the widget. Two copies of these numbers would eventually
/// disagree, and the symptom — a hover zone offset from the visible pill — is
/// unpleasant to track down.
class RailMetrics {
  const RailMetrics({
    required this.collapsedWidth,
    required this.expandedWidth,
    required this.slotHeight,
    required this.collapsedVerticalPadding,
    required this.shadowPadding,
    required this.edgeInset,
    required this.windowWidth,
    required this.windowHeight,
    required this.slots,
  });

  final double collapsedWidth;
  final double expandedWidth;
  final double slotHeight;
  final double collapsedVerticalPadding;
  final double shadowPadding;
  final double edgeInset;
  final double windowWidth;
  final double windowHeight;
  final int slots;

  /// Used before native replies, and under `flutter test` where there is no
  /// native side at all. Matches the Swift defaults.
  static const RailMetrics fallback = RailMetrics(
    collapsedWidth: 62,
    expandedWidth: 296,
    slotHeight: 66,
    collapsedVerticalPadding: 14,
    shadowPadding: 26,
    edgeInset: 6,
    windowWidth: 348,
    windowHeight: 520,
    slots: 4,
  );

  double get collapsedHeight =>
      slots * slotHeight + collapsedVerticalPadding * 2;

  /// Vertical centre of a provider's ring, in the window's coordinate space.
  ///
  /// The hover card is positioned from this so its tail lands on the ring it
  /// describes. Derived from the same numbers Swift used to size the window,
  /// so the tail cannot drift away from the ring.
  double slotCenterY(int index) {
    final columnTop = (windowHeight - collapsedHeight) / 2;
    return columnTop +
        collapsedVerticalPadding +
        index * slotHeight +
        slotHeight / 2;
  }

  static RailMetrics? fromMap(Object? value) {
    if (value is! Map) return null;
    double? number(String key) {
      final v = value[key];
      return v is num ? v.toDouble() : null;
    }

    final slots = value['slots'];
    final width = number('windowWidth');
    final height = number('windowHeight');
    if (slots is! int || width == null || height == null) return null;

    return RailMetrics(
      collapsedWidth: number('collapsedWidth') ?? fallback.collapsedWidth,
      expandedWidth: number('expandedWidth') ?? fallback.expandedWidth,
      slotHeight: number('slotHeight') ?? fallback.slotHeight,
      collapsedVerticalPadding:
          number('collapsedVerticalPadding') ??
          fallback.collapsedVerticalPadding,
      shadowPadding: number('shadowPadding') ?? fallback.shadowPadding,
      edgeInset: number('edgeInset') ?? fallback.edgeInset,
      windowWidth: width,
      windowHeight: height,
      slots: slots,
    );
  }
}

/// The single seam between Flutter and the Swift/AppKit layer.
///
/// Everything macOS-specific lives behind this class: the rail window, the
/// setup panel, the status item, login-item registration, Keychain storage,
/// process inspection, and opening URLs. No widget or provider imports a
/// MethodChannel or any platform detail directly.
class NativeBridge {
  NativeBridge({MethodChannel? channel, Logger? logger})
    : _channel = channel ?? const MethodChannel(channelName),
      _log = logger ?? const Logger('native') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const String channelName = 'com.aiusagemonitor/native';

  final MethodChannel _channel;
  final Logger _log;

  /// The pointer entered or left the rail.
  void Function(bool expanded)? onExpansionChanged;

  /// The window switched between the rail and the setup panel.
  void Function(String mode)? onModeChanged;

  void Function()? onRefreshRequested;
  void Function()? onSettingsRequested;
  void Function()? onRailToggleRequested;

  /// A provider's browser sign-in came back through the registered URL scheme.
  void Function(Uri url)? onAuthCallback;

  Future<void> _handleNativeCall(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'rail.expansionChanged':
        final expanded = args?['expanded'];
        if (expanded is bool) onExpansionChanged?.call(expanded);
      case 'window.modeChanged':
        final mode = args?['mode'];
        if (mode is String) onModeChanged?.call(mode);
      case 'refreshRequested':
        onRefreshRequested?.call();
      case 'settingsRequested':
        onSettingsRequested?.call();
      case 'railToggleRequested':
        onRailToggleRequested?.call();
      case 'auth.callback':
        final raw = args?['url'];
        if (raw is String) {
          final parsed = Uri.tryParse(raw);
          if (parsed != null) onAuthCallback?.call(parsed);
        }
      default:
        _log.warn('unhandled native call: ${call.method}');
    }
  }

  // MARK: - Rail

  /// Reads the geometry the window is actually laid out with.
  Future<RailMetrics> railMetrics() async {
    final raw = await _invoke<Map<Object?, Object?>>('rail.metrics');
    return RailMetrics.fromMap(raw) ?? RailMetrics.fallback;
  }

  /// Places the rail. [offset] is measured from the top of the usable screen
  /// area, 0.5 being centred.
  Future<void> configureRail({
    required RailEdge edge,
    required double offset,
    String? screenId,
  }) async {
    await _invoke<void>('rail.configure', {
      'edge': edge.name,
      'offset': offset,
      'screenId': screenId,
    });
  }

  Future<void> showRail({required bool pinnedOpen}) =>
      _invoke<void>('rail.show', {'pinnedOpen': pinnedOpen});

  Future<void> hideRail() => _invoke<void>('rail.hide');

  /// Keeps the rail open regardless of where the pointer is.
  Future<void> setRailPinnedOpen(bool pinned) =>
      _invoke<void>('rail.setPinnedOpen', {'pinned': pinned});

  /// Opens the rail without waiting for a hover.
  Future<void> expandRail() => _invoke<void>('rail.expand');

  // MARK: - Setup panel

  Future<void> showPanel({required Size size}) =>
      _invoke<void>('panel.show', {'width': size.width, 'height': size.height});

  Future<void> hidePanel() => _invoke<void>('panel.hide');

  // MARK: - Screens

  Future<List<NativeScreen>> listScreens() async {
    final raw = await _invoke<List<Object?>>('screens.list');
    if (raw == null) return const [];
    return raw.map(NativeScreen.fromMap).whereType<NativeScreen>().toList();
  }

  // MARK: - Menu bar

  /// Updates the menu-bar item, which is a fallback control rather than the
  /// primary surface.
  ///
  /// [percent] is null when usage is unknown, which renders as a dash so the
  /// menu bar never implies a number the app does not have.
  Future<void> updateMenuBar({
    required bool showIcon,
    required bool showPercent,
    int? percent,
    bool isError = false,
  }) async {
    await _invoke<void>('menuBar.update', {
      'showIcon': showIcon,
      'showPercent': showPercent,
      'percent': percent,
      'isError': isError,
    });
  }

  // MARK: - System

  /// Opens [url] in the user's default browser. Returns false when macOS
  /// refused, so a connect flow can say so rather than appearing to hang.
  Future<bool> openUrl(Uri url) async {
    return await _invoke<bool>('url.open', {'url': url.toString()}) ?? false;
  }

  Future<bool> isLaunchAtLoginEnabled() async {
    return await _invoke<bool>('loginItem.isEnabled') ?? false;
  }

  /// Returns true when the change was applied.
  Future<bool> setLaunchAtLogin(bool enabled) async {
    return await _invoke<bool>('loginItem.setEnabled', {'enabled': enabled}) ??
        false;
  }

  /// Reads a secret from the macOS Keychain. Returns null when absent.
  Future<String?> readSecret(String key) =>
      _invoke<String>('keychain.read', {'key': key});

  /// Stores a secret in the macOS Keychain, or removes it when [value] is null.
  Future<bool> writeSecret(String key, String? value) async {
    return await _invoke<bool>('keychain.write', {
          'key': key,
          'value': value,
        }) ??
        false;
  }

  /// Reads the credential blob Claude Code keeps in the login Keychain.
  ///
  /// Used for one thing: asking Anthropic for the account's current usage, so
  /// the rail shows the live figure rather than the copy Claude Code last
  /// cached. The token is never stored, logged, or refreshed.
  ///
  /// macOS asks the user to approve the first read, because the item belongs to
  /// Claude Code rather than to this app. A refusal returns
  /// [ClaudeCodeCredentialAccess.denied] so the caller can fall back to the
  /// cache instead of reporting the account as broken.
  Future<ClaudeCodeCredentialAccess> readClaudeCodeCredentials() async {
    final raw = await _invoke<Map<Object?, Object?>>('keychain.claudeCode');
    if (raw == null) return const ClaudeCodeCredentialAccess.absent();

    final value = raw['value'];
    return switch (raw['status']) {
      'found' when value is String && value.isNotEmpty =>
        ClaudeCodeCredentialAccess.found(value),
      'denied' => const ClaudeCodeCredentialAccess.denied(),
      _ => const ClaudeCodeCredentialAccess.absent(),
    };
  }

  /// Lists running processes matching [executableNames].
  Future<List<NativeProcessInfo>> findProcesses(
    List<String> executableNames,
  ) async {
    final raw = await _invoke<List<Object?>>('process.find', {
      'names': executableNames,
    });
    if (raw == null) return const [];
    return raw
        .map(NativeProcessInfo.fromMap)
        .whereType<NativeProcessInfo>()
        .toList();
  }

  /// Asks the user to choose a file, returning its path or null if cancelled.
  Future<String?> pickFile({
    required String title,
    List<String> extensions = const [],
  }) {
    return _invoke<String>('dialog.openFile', {
      'title': title,
      'extensions': extensions,
    });
  }

  // MARK: - Official CLIs

  /// Resolves an installed CLI to its absolute path, or null when it is not
  /// on this machine.
  ///
  /// Cannot be done in Dart: an app launched from Finder has almost nothing on
  /// its `PATH`, so `Process.run('which', …)` finds none of these tools.
  Future<String?> locateCli(String name) =>
      _invoke<String>('cli.which', {'name': name});

  /// Runs an official CLI under a pseudo-terminal and returns what it drew.
  ///
  /// Used for providers whose quota is only shown in an interactive panel.
  /// The CLI authenticates itself exactly as it would if the user ran it; this
  /// app never sees or stores its credentials.
  Future<CliProbeResult> probeCli({
    required String executable,
    List<String> arguments = const [],
    required List<CliProbeStep> steps,
    Duration timeout = const Duration(seconds: 75),
    int columns = 120,
    int rows = 45,
    String? workingDirectory,
  }) async {
    final raw = await _invoke<Map<Object?, Object?>>('cli.probe', {
      'executable': executable,
      'arguments': arguments,
      'steps': [for (final step in steps) step.toJson()],
      'timeout': timeout.inMilliseconds / 1000,
      'columns': columns,
      'rows': rows,
      'workingDirectory': workingDirectory,
    });
    return CliProbeResult.fromMap(raw) ?? CliProbeResult.unavailable;
  }

  Future<void> quit() => _invoke<void>('app.quit');

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Expected under `flutter test`, where no native side exists.
      _log.debug('no native handler for $method');
      return null;
    } on PlatformException catch (e) {
      _log.error('native call $method failed', e.code);
      return null;
    }
  }
}
