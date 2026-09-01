import 'dart:io';

import '../../core/logger.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'agent_session_store.dart';
import 'agent_usage_provider.dart';

/// OpenCode, read from the session store it keeps under `~/.local/share`.
class OpenCodeUsageProvider extends AgentUsageProvider {
  OpenCodeUsageProvider({
    required super.native,
    required super.connectionStore,
    super.store,
    this.homeDirectory,
    Logger? logger,
  }) : super(logger: logger ?? const Logger('opencode'));

  /// Overridden in tests so the suite never reads the developer's own store.
  final String? homeDirectory;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.openCode;

  @override
  AgentUsageReader buildStore() {
    final home = homeDirectory ?? Platform.environment['HOME'] ?? '';
    return AgentSessionStore(
      databasePath: '$home/.local/share/opencode/opencode.db',
      // Where OpenCode caches models.dev, which carries each model's published
      // context window — the limit the percentage is against.
      modelCatalogPath: '$home/.cache/opencode/models.json',
      displayName: descriptor.displayName,
      logger: log,
    );
  }

  /// What the user types to start it.
  @override
  String get executableName => 'opencode';

  @override
  String get sourceDescription =>
      'The context figure OpenCode shows for the model you are on, read from '
      'its own session database and measured against that model’s published '
      'context window. The weekly total is against your own token budget.';
}
