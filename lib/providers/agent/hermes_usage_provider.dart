import 'dart:io';

import '../../core/logger.dart';
import '../provider_catalog.dart';
import '../usage_provider.dart';
import 'agent_session_store.dart';
import 'agent_usage_provider.dart';
import 'hermes_insights_source.dart';

/// Hermes Agent.
///
/// Unlike OpenCode and Kilo Code, Hermes keeps no session database this app can
/// open — `state.db` is not readable from outside the agent. It does publish
/// the same facts through its own commands, so those are the source: `insights`
/// for what each model has spent, `status` for the model it is set to.
///
/// The consequence is that this reading costs a process launch rather than a
/// file read, which is why the window is checked against the sessions directory
/// first and the report is only run when something has actually changed.
class HermesUsageProvider extends AgentUsageProvider {
  HermesUsageProvider({
    required super.native,
    required super.connectionStore,
    super.store,
    this.homeDirectory,
    Logger? logger,
  }) : super(logger: logger ?? const Logger('hermes'));

  /// Overridden in tests so the suite never runs the developer's own Hermes.
  final String? homeDirectory;

  @override
  ProviderDescriptor get descriptor => ProviderCatalog.hermes;

  @override
  AgentUsageReader buildStore() {
    final home = homeDirectory ?? Platform.environment['HOME'] ?? '';
    return HermesInsightsSource(
      executable: '$home/.local/bin/hermes',
      sessionsDirectory: '$home/.hermes/sessions',
      authPath: '$home/.hermes/auth.json',
      logger: log,
    );
  }

  /// A report that starts a Python process is not something to run every half
  /// minute. The sessions directory is watched for the immediate signal; this
  /// is only the backstop.
  @override
  Duration? get preferredRefreshInterval => const Duration(minutes: 5);

  @override
  String get executableName => 'hermes';

  @override
  String get sourceDescription =>
      'Tokens Hermes reports through its own insights command, for the model '
      'it is set to. Hermes publishes no allowance, so the figure is shown '
      'against your weekly token budget.';
}
