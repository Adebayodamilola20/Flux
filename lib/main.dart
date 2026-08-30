import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/logger.dart';
import 'providers/claude/claude_usage_provider.dart';
import 'providers/provider_catalog.dart';
import 'providers/provider_registry.dart';
import 'providers/reserved_provider.dart';
import 'services/connection_store.dart';
import 'services/history_service.dart';
import 'services/native/native_bridge.dart';
import 'services/settings_service.dart';
import 'services/shell_controller.dart';
import 'services/usage_controller.dart';

/// Composition root.
///
/// Wires the object graph once and hands it to the widget tree. Nothing below
/// this point constructs its own dependencies, which is what makes the whole
/// app testable with fakes.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const log = Logger('boot');

  final preferences = await SharedPreferences.getInstance();
  final native = NativeBridge();

  final settingsService = SettingsService(
    preferences: preferences,
    native: native,
  );
  await settingsService.load();

  final historyService = HistoryService(preferences: preferences);
  final connectionStore = ConnectionStore(preferences: preferences);

  // The three slots, in rail order. Claude is integrated; the other two are
  // reserved and refuse honestly rather than pretending to work. Replacing one
  // is a single line here plus its implementation.
  final registry = ProviderRegistry([
    ClaudeUsageProvider(native: native, connectionStore: connectionStore),
    ReservedProvider(ProviderCatalog.codex),
    ReservedProvider(ProviderCatalog.antigravity),
  ]);

  final usageController = UsageController(
    registry: registry,
    settingsService: settingsService,
    historyService: historyService,
    native: native,
  );

  final shellController = ShellController(
    native: native,
    settingsService: settingsService,
    usageController: usageController,
  );

  runApp(
    AiUsageMonitorApp(
      native: native,
      registry: registry,
      settingsService: settingsService,
      historyService: historyService,
      usageController: usageController,
      shellController: shellController,
    ),
  );

  // Deliberately not deferred to a post-frame callback. The app launches with
  // no window on screen, and an off-screen Flutter view is not guaranteed to
  // produce a frame — waiting for one would mean the code that decides which
  // window to show never runs at all.
  unawaited(_boot(usageController, shellController, log));
}

Future<void> _boot(
  UsageController usage,
  ShellController shell,
  Logger log,
) async {
  try {
    // Connections first: which surface to show depends on whether anything has
    // been connected, so the shell must not decide before it knows.
    await usage.start();
    await shell.start();
  } catch (e, stack) {
    log.error('startup failed', e.runtimeType, stack);
  }
}
