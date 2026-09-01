import 'dart:io';

import '../../core/logger.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'agent_session_store.dart';
import 'agent_usage_provider.dart';

/// Kilo Code.
///
/// A fork of OpenCode, and it kept the session schema: same `session` table,
/// same model JSON, same token columns. Only the path differs, which is why
/// this is a path and a descriptor rather than a second implementation.
class KiloCodeUsageProvider extends AgentUsageProvider {
  KiloCodeUsageProvider({
    required super.native,
    required super.connectionStore,
    super.store,
    this.homeDirectory,
    Logger? logger,
  }) : super(logger: logger ?? const Logger('kilocode'));

  /// Overridden in tests so the suite never reads the developer's own store.
  final String? homeDirectory;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.kiloCode;

  @override
  AgentUsageReader buildStore() {
    final home = homeDirectory ?? Platform.environment['HOME'] ?? '';
    return AgentSessionStore(
      databasePath: '$home/.local/share/kilo/kilo.db',
      modelCatalogPath: '$home/.cache/kilo/models.json',
      displayName: descriptor.displayName,
      logger: log,
    );
  }

  /// The command is `kilo`, not the product name — which is exactly the kind
  /// of thing a "run it once" instruction has to get right.
  @override
  String get executableName => 'kilo';

  @override
  String get sourceDescription =>
      'The context figure Kilo Code shows for the model you are on, read from '
      'its own session database and measured against that model’s published '
      'context window. The weekly total is against your own token budget.';
}
