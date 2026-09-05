import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/logger.dart';
import 'providers/api/chatgpt_provider.dart';
import 'providers/claude/claude_usage_provider.dart';
import 'providers/agent/hermes_usage_provider.dart';
import 'providers/agent/kilocode_usage_provider.dart';
import 'providers/agent/opencode_usage_provider.dart';
import 'providers/antigravity/antigravity_usage_provider.dart';
import 'providers/provider_registry.dart';
import 'services/auth/oauth_registry.dart';
import 'services/connection_store.dart';
import 'services/history_service.dart';
import 'services/native/native_bridge.dart';
import 'services/settings_service.dart';
import 'services/shell_controller.dart';
import 'services/update_checker.dart';
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
  // Kept for the settings screen, which can still register an OAuth client for
  // a future provider. No shipped slot uses one — every one of them reads a
  // tool that is already signed in on this Mac.
  final oauthRegistry = OAuthRegistry(preferences: preferences);

  // Everything this build can measure -- not a rail. The rail has three
  // positions and the user decides which of these go in them; see
  // `UsageController.slots`.
  //
  // None of them asks the user to sign in. Each reads a tool that is already
  // installed and already authenticated on this Mac, because for these
  // providers an account link would grant the app nothing the local tool does
  // not already have.
  final registry = ProviderRegistry([
    ClaudeUsageProvider(native: native, connectionStore: connectionStore),
    ChatGptProvider(native: native, connectionStore: connectionStore),
    OpenCodeUsageProvider(native: native, connectionStore: connectionStore),
    KiloCodeUsageProvider(native: native, connectionStore: connectionStore),
    AntigravityUsageProvider(native: native, connectionStore: connectionStore),
    HermesUsageProvider(native: native, connectionStore: connectionStore),
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

  // Looks for a newer published build, later and then every few hours. It
  // only ever reports; installing is the user's, see UpdateChecker.
  final updateChecker = UpdateChecker(
    installedBuild: UpdateChecker.compiledBuild,
  )..start();

  runApp(
    AiUsageMonitorApp(
      native: native,
      registry: registry,
      settingsService: settingsService,
      historyService: historyService,
      usageController: usageController,
      shellController: shellController,
      oauthRegistry: oauthRegistry,
      updateChecker: updateChecker,
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
  // What the user sees comes first.
  //
  // This used to fetch every provider's usage before deciding which window to
  // open, on the reasoning that the decision might depend on it. It does not —
  // the only question is whether onboarding has been completed — and the cost
  // was severe: a CLI probe takes the better part of a minute, a Keychain
  // dialog waits on the user indefinitely, and until all of it finished the
  // app had no window at all. On a first run that meant the intro screen did
  // not appear, which looked exactly like an app that had failed to start.
  //
  // So: restore what is already on disk, put the right window on screen, and
  // only then go and ask anyone anything.
  try {
    await usage.restore();
  } catch (e, stack) {
    log.error('restoring providers failed', e.runtimeType, stack);
  }

  try {
    await shell.start();
  } catch (e, stack) {
    log.error('startup failed', e.runtimeType, stack);
  }

  // Separately guarded: a provider that cannot be reached must not take the
  // window down with it.
  try {
    usage.beginPolling();
    await usage.refreshAll();
  } catch (e, stack) {
    log.error('first refresh failed', e.runtimeType, stack);
  }
}
