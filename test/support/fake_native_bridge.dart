import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [NativeBridge] backed by an in-memory fake of the macOS layer.
///
/// Exercises the real channel-encoding path — arguments go through the platform
/// message codec exactly as they would in the app — while letting tests assert
/// on what the native side was asked to do.
class FakeNativeBridge extends NativeBridge {
  FakeNativeBridge._(this._channel, this._state) : super(channel: _channel);

  factory FakeNativeBridge() {
    final state = _FakeNativeState();
    const channel = MethodChannel('com.aiusagemonitor/native.fake');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, state.handle);

    return FakeNativeBridge._(channel, state);
  }

  final MethodChannel _channel;
  final _FakeNativeState _state;

  /// Channel name to target when simulating a call *from* the native side.
  String get channelName => _channel.name;

  /// Every `menuBar.update` call, in order.
  List<MenuBarUpdate> get menuBarUpdates => _state.menuBarUpdates;

  /// Every `rail.configure` call, in order.
  List<RailPlacementCall> get placements => _state.placements;

  /// Secrets currently held by the fake Keychain.
  Map<String, String> get secrets => _state.secrets;

  /// URLs the app asked macOS to open in the browser.
  List<String> get openedUrls => _state.openedUrls;

  bool get launchAtLogin => _state.launchAtLogin;
  bool get isRailVisible => _state.isRailVisible;
  bool get isPanelVisible => _state.isPanelVisible;
  List<Size> get panelSizes => _state.panelSizes;
  int get expandCount => _state.expandCount;
  bool get didQuit => _state.didQuit;

  /// When false, the fake refuses login-item registration, as macOS does when
  /// the user has the item disabled in System Settings.
  set allowLoginItemChanges(bool value) => _state.allowLoginItemChanges = value;

  /// When false, `url.open` reports failure, as macOS does when no handler is
  /// registered for the scheme.
  set allowUrlOpen(bool value) => _state.allowUrlOpen = value;

  set processes(List<Map<String, Object?>> value) => _state.processes = value;

  set screens(List<Map<String, Object?>> value) => _state.screens = value;

  /// Absolute paths the fake reports for installed CLIs, keyed by name.
  /// Anything absent is treated as not installed.
  Map<String, String> get installedClis => _state.installedClis;

  /// What the next `cli.probe` returns. Set to a recorded panel capture to
  /// exercise a provider against real CLI output.
  set probeResult(Map<String, Object?> value) => _state.probeResult = value;

  /// Every `cli.probe` request, in order.
  List<CliProbeCall> get probes => _state.probes;

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

/// One recorded menu-bar update.
class MenuBarUpdate {
  const MenuBarUpdate({
    required this.showIcon,
    required this.showPercent,
    required this.percent,
    required this.isError,
  });

  final bool showIcon;
  final bool showPercent;
  final int? percent;
  final bool isError;

  @override
  String toString() =>
      'MenuBarUpdate(icon: $showIcon, percent: $percent, error: $isError)';
}

/// One recorded `cli.probe` call.
class CliProbeCall {
  const CliProbeCall({
    required this.executable,
    required this.steps,
    required this.timeout,
    this.workingDirectory,
  });

  final String executable;

  /// Where the CLI was told to run. Recorded because running these tools in
  /// the app's own directory — `/` for anything launched from Finder — makes
  /// them index the whole filesystem and time out.
  final String? workingDirectory;

  /// The scripted keystrokes, as `(seconds, keys)` pairs.
  final List<(double, String)> steps;

  final double timeout;

  @override
  String toString() => 'CliProbeCall($executable, ${steps.length} steps)';
}

/// One recorded `rail.configure` call.
class RailPlacementCall {
  const RailPlacementCall({
    required this.edge,
    required this.offset,
    required this.screenId,
  });

  final String edge;
  final double offset;
  final String? screenId;

  @override
  String toString() =>
      'RailPlacementCall($edge, offset: $offset, screen: $screenId)';
}

class _FakeNativeState {
  final menuBarUpdates = <MenuBarUpdate>[];
  final placements = <RailPlacementCall>[];
  final secrets = <String, String>{};
  final openedUrls = <String>[];
  final panelSizes = <Size>[];

  bool launchAtLogin = false;
  bool allowLoginItemChanges = true;
  bool allowUrlOpen = true;
  bool didQuit = false;
  bool isRailVisible = false;
  bool isPanelVisible = false;
  int expandCount = 0;
  List<Map<String, Object?>> processes = const [];
  List<Map<String, Object?>> screens = const [
    {'id': '1', 'name': 'Built-in Display', 'isPrimary': true},
  ];

  final Map<String, String> installedClis = {};
  final List<CliProbeCall> probes = [];
  Map<String, Object?> probeResult = const {
    'output': '',
    'launched': false,
    'timedOut': false,
    'failure': 'not installed',
  };

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};

    switch (call.method) {
      case 'rail.metrics':
        return <String, Object?>{
          'collapsedWidth': 62.0,
          'expandedWidth': 296.0,
          'slotHeight': 66.0,
          'collapsedVerticalPadding': 14.0,
          'shadowPadding': 26.0,
          'edgeInset': 6.0,
          'windowWidth': 348.0,
          'windowHeight': 520.0,
          'slots': 4,
        };

      case 'rail.configure':
        placements.add(
          RailPlacementCall(
            edge: args['edge'] as String,
            offset: args['offset'] as double,
            screenId: args['screenId'] as String?,
          ),
        );
        return null;

      case 'rail.show':
        isRailVisible = true;
        isPanelVisible = false;
        return null;

      case 'rail.hide':
        isRailVisible = false;
        return null;

      case 'rail.setPinnedOpen':
        return null;

      case 'rail.expand':
        expandCount++;
        return null;

      case 'panel.show':
        isPanelVisible = true;
        panelSizes.add(Size(args['width'] as double, args['height'] as double));
        return null;

      case 'panel.hide':
        isPanelVisible = false;
        return null;

      case 'screens.list':
        return screens;

      case 'url.open':
        if (!allowUrlOpen) return false;
        openedUrls.add(args['url'] as String);
        return true;

      case 'menuBar.update':
        menuBarUpdates.add(
          MenuBarUpdate(
            showIcon: args['showIcon'] as bool,
            showPercent: args['showPercent'] as bool,
            percent: args['percent'] as int?,
            isError: args['isError'] as bool,
          ),
        );
        return null;

      case 'loginItem.isEnabled':
        return launchAtLogin;

      case 'loginItem.setEnabled':
        if (!allowLoginItemChanges) return launchAtLogin;
        launchAtLogin = args['enabled'] as bool;
        return launchAtLogin;

      case 'keychain.read':
        return secrets[args['key'] as String];

      case 'keychain.write':
        final key = args['key'] as String;
        final value = args['value'] as String?;
        if (value == null || value.isEmpty) {
          secrets.remove(key);
        } else {
          secrets[key] = value;
        }
        return true;

      case 'process.find':
        final names = (args['names'] as List).cast<String>();
        return processes
            .where((p) => names.contains(p['name']))
            .toList(growable: false);

      case 'cli.which':
        return installedClis[args['name'] as String];

      case 'cli.probe':
        probes.add(
          CliProbeCall(
            executable: args['executable'] as String,
            steps: [
              for (final step in (args['steps'] as List).cast<Map>())
                (step['at'] as double, step['keys'] as String),
            ],
            timeout: args['timeout'] as double,
            workingDirectory: args['workingDirectory'] as String?,
          ),
        );
        return probeResult;

      case 'app.quit':
        didQuit = true;
        return null;

      default:
        throw MissingPluginException(call.method);
    }
  }
}
