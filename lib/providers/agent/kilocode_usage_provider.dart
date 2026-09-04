import 'dart:io';

import '../../core/logger.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'agent_session_store.dart';
import 'agent_usage_provider.dart';

/// Kilo Code.
///
/// A fork of OpenCode, sharing its `session` table and model JSON, which is
/// why this is a path and a descriptor rather than a second implementation.
///
/// The schemas are not identical, though: Kilo Code forked before OpenCode
/// began totalling each session onto its row, so its `session` table carries
/// no token columns. [AgentSessionStore] detects that and rebuilds the totals
/// from the assistant turns instead.
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
      authPath: '$home/.local/share/kilo/auth.json',
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
