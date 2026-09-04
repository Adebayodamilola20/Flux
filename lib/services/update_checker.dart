import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/logger.dart';

/// What the published manifest says the current release is.
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.downloadUrl,
    this.notes,
  });

  /// Marketing version, e.g. `1.0.0`. Shown, not compared.
  final String version;

  /// Build stamp, `yyyyMMddHHmm` in UTC. Compared: a later stamp is newer.
  final String build;

  /// Where the disk image is.
  final Uri downloadUrl;

  /// One or two lines on what changed.
  final String? notes;

  /// Reads the manifest `tool/package_dmg.sh` publishes.
  ///
  /// Null for anything that does not carry the fields — a manifest this app
  /// cannot read is not an update, it is a manifest to ignore.
  static UpdateInfo? parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['version'];
    final build = decoded['build'];
    final url = decoded['url'];
    if (version is! String || build is! String || url is! String) return null;
    if (!isBuildStamp(build)) return null;

    final downloadUrl = Uri.tryParse(url);
    if (downloadUrl == null || !downloadUrl.hasScheme) return null;

    final notes = decoded['notes'];
    return UpdateInfo(
      version: version,
      build: build,
      downloadUrl: downloadUrl,
      notes: notes is String && notes.isNotEmpty ? notes : null,
    );
  }

  /// Twelve digits, so two stamps compare as strings.
  static bool isBuildStamp(String s) => RegExp(r'^\d{12}$').hasMatch(s);

  /// True when this manifest describes a build newer than [installed].
  ///
  /// An installed build with no stamp — a developer run — never counts as out
  /// of date, so `flutter run` does not nag.
  bool isNewerThan(String installed) =>
      isBuildStamp(installed) && build.compareTo(installed) > 0;
}

/// Tells the user when a newer DevNotch has been published.
///
/// **Why this and not an in-app installer.** Replacing a running app bundle
/// under itself needs a signed updater framework and a notarised build for
/// macOS to trust the swap; this app is ad-hoc signed. What can be done
/// honestly is to notice a newer build and hand the user the download, which
/// is what this does. The check is one small GET of a JSON manifest that the
/// packaging script publishes next to the disk image; nothing about this Mac
/// is sent with it.
///
/// **What "newer" means.** The marketing version stays at 1.0.0 while the
/// release asset is replaced in place, so a version string cannot tell two
/// builds apart. The packaging script stamps each build with the minute it was
/// made, and that stamp is what is compared.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    required this.installedBuild,
    Uri? manifestUrl,
    http.Client? client,
    Duration checkInterval = const Duration(hours: 6),
    Logger? logger,
  })  : _manifestUrl = manifestUrl ?? defaultManifestUrl,
        _client = client ?? http.Client(),
        _interval = checkInterval,
        _log = logger ?? const Logger('update');

  /// The build stamp compiled into this binary, from `--dart-define`.
  ///
  /// Empty in a developer run, which [UpdateInfo.isNewerThan] treats as
  /// never out of date.
  static const String compiledBuild = String.fromEnvironment('BUILD_STAMP');

  /// The marketing version, passed by the packaging script from pubspec so
  /// the two cannot drift. The default covers a plain `flutter run`.
  static const String compiledVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');

  /// Resolves to the newest release's manifest whatever its tag is, so a new
  /// tag does not strand older installs on an old URL.
  static final Uri defaultManifestUrl = Uri.parse(
    'https://github.com/Adebayodamilola20/Flux/releases/latest/download/latest.json',
  );

  /// How long after launch the first check runs. Late enough not to compete
  /// with the first usage fetches, which are what the user opened it for.
  static const Duration firstCheckDelay = Duration(seconds: 45);

  final String installedBuild;
  final Uri _manifestUrl;
  final http.Client _client;
  final Duration _interval;
  final Logger _log;

  Timer? _timer;
  bool _disposed = false;

  UpdateInfo? _available;
  bool _checking = false;
  DateTime? _lastChecked;
  String? _lastError;

  /// The newer build, when there is one. Null when up to date or unknown.
  UpdateInfo? get available => _available;

  bool get isChecking => _checking;

  DateTime? get lastChecked => _lastChecked;

  /// Why the last check produced no answer, for the settings row to say.
  String? get lastError => _lastError;

  /// Schedules the periodic check. Safe to call once at boot.
  void start() {
    _timer?.cancel();
    _timer = Timer(firstCheckDelay, () {
      unawaited(check());
      _timer = Timer.periodic(_interval, (_) => unawaited(check()));
    });
  }

  /// Fetches the manifest and compares it to the installed build.
  ///
  /// Returns the update when there is one. Never throws: a Mac that is
  /// offline simply stays on its current build, and the row says the check
  /// did not go through.
  Future<UpdateInfo?> check() async {
    if (_checking) return _available;
    _checking = true;
    _lastError = null;
    _notify();

    try {
      final response = await _client
          .get(_manifestUrl, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _lastError = 'The update server answered ${response.statusCode}.';
        _log.debug('manifest fetch returned ${response.statusCode}');
        return _available;
      }

      final info = UpdateInfo.parse(response.body);
      if (info == null) {
        _lastError = 'The update information could not be read.';
        _log.warn('manifest did not parse');
        return _available;
      }

      _available = info.isNewerThan(installedBuild) ? info : null;
      _log.info(
        _available == null
            ? 'up to date (installed $installedBuild, published ${info.build})'
            : 'update available: ${info.version} build ${info.build}',
      );
      return _available;
    } catch (e) {
      _lastError = 'Could not reach the update server.';
      _log.debug('update check failed: ${e.runtimeType}');
      return _available;
    } finally {
      _lastChecked = DateTime.now();
      _checking = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}
