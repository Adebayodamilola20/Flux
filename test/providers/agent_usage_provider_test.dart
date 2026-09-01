import 'dart:io';

import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/connection_status.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/agent/agent_session_store.dart';
import 'package:ai_usage_monitor/providers/agent/hermes_insights_source.dart';
import 'package:ai_usage_monitor/providers/agent/opencode_usage_provider.dart';
import 'package:ai_usage_monitor/services/connection_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_native_bridge.dart';

/// A reader standing in for a session database, so these tests never depend on
/// whether the developer happens to have OpenCode installed.
class _StubReader implements AgentUsageReader {
  _StubReader({this.reading, this.available = true});

  AgentUsageReading? reading;
  bool available;
  int reads = 0;

  @override
  bool get isAvailable => available;

  @override
  DateTime? get changedAt => null;

  @override
  Future<AgentUsageReading> read({Duration window = const Duration(days: 7)}) {
    reads++;
    return Future.value(
      reading ?? const AgentUsageReading.unavailable('nothing recorded'),
    );
  }
}

AgentModelUsage _model(
  String id, {
  int tokens = 1000,
  int sessions = 2,
  int? contextTokens,
  int? contextLimit,
}) {
  return AgentModelUsage(
    model: id,
    provider: 'nvidia',
    tokens: tokens,
    sessions: sessions,
    lastUsedAt: DateTime.now(),
    contextTokens: contextTokens,
    contextLimit: contextLimit,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNativeBridge native;
  late SharedPreferences preferences;

  setUp(() async {
    native = FakeNativeBridge();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() => native.dispose());

  OpenCodeUsageProvider build(_StubReader reader) {
    return OpenCodeUsageProvider(
      native: native,
      connectionStore: ConnectionStore(preferences: preferences),
      store: reader,
    );
  }

  group('the model in use', () {
    test('names the window after it, not after the tool', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('deepseek-v3', tokens: 4000)],
          active: _model(
            'deepseek-v3',
            tokens: 4000,
            contextTokens: 12000,
            contextLimit: 128000,
          ),
        ),
      );
      final provider = build(reader);

      final data = await provider.fetchUsage(const AppSettings());

      // The ring already says OpenCode. What the user cannot otherwise tell is
      // which model the figure belongs to.
      expect(data.windows.first.label, 'deepseek-v3');
      expect(data.accountLabel, 'deepseek-v3');
    });

    test('reports the model switched *to*, not the one left behind', () async {
      // Running out on one model and moving to another is the normal way these
      // tools are used, and it makes the previous number meaningless.
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [
            _model('deepseek-v3', tokens: 900000),
            _model('kimi-k2', tokens: 1200),
          ],
          active: _model(
            'kimi-k2',
            tokens: 1200,
            contextTokens: 800,
            contextLimit: 200000,
          ),
        ),
      );
      final provider = build(reader);

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows.first.label, 'kimi-k2');
      expect(
        data.windows.firstWhere((w) => w.id == 'weekly_tokens').consumed,
        1200,
      );
      // The model they left is not forgotten, just not the headline.
      expect(
        data.notes.any((n) => n.contains('deepseek-v3')),
        isTrue,
        reason: 'the week’s other models should still be visible somewhere',
      );
    });

    test('a switch updates what the connection says it is on', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('deepseek-v3')],
          active: _model('deepseek-v3'),
        ),
      );
      final provider = build(reader);
      await provider.fetchUsage(const AppSettings());
      expect(provider.connection.accountLabel, 'deepseek-v3');

      reader.reading = AgentUsageReading(
        models: [_model('kimi-k2')],
        active: _model('kimi-k2'),
      );
      await provider.fetchUsage(const AppSettings());

      expect(provider.connection.accountLabel, 'kimi-k2');
    });
  });

  group('the figure the tool itself shows', () {
    test('is the context, against the model’s published window', () async {
      // OpenCode's own status line read "9,703 tokens · 5% used" while the
      // rail read 0%, because the rail was reporting a week against a budget
      // of a billion. Both were true; only one was the number being asked
      // about.
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('big-pickle', tokens: 1677935)],
          active: _model(
            'big-pickle',
            tokens: 1677935,
            contextTokens: 9703,
            contextLimit: 200000,
          ),
        ),
      );

      final data = await build(reader).fetchUsage(const AppSettings());
      final context = data.windows.first;

      expect(context.id, 'context');
      expect(context.consumed, 9703);
      expect(context.limit, 200000);
      expect(context.percentUsed, 5);
      // The count and the ceiling both come from the tool's own records, so
      // this is not an estimate.
      expect(context.source, UsageSource.officialCli);
    });

    test('is a count, not a percentage, for an unlisted model', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('something-new')],
          active: _model('something-new', contextTokens: 4200),
        ),
      );

      final data = await build(reader).fetchUsage(const AppSettings());
      final context = data.windows.first;

      // No published window for it, so there is nothing honest to divide by.
      expect(context.limit, isNull);
      expect(context.percentUsed, isNull);
      expect(data.notes.any((n) => n.contains('No published context')), isTrue);
    });
  });

  group('what the figure is measured against', () {
    test('is the user’s budget, and says so', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('glm-5.2', tokens: 500)],
          active: _model('glm-5.2', tokens: 500),
        ),
      );
      final provider = build(reader);

      final data = await provider.fetchUsage(
        const AppSettings(weeklyTokenBudget: 1000),
      );
      final window = data.windows.firstWhere((w) => w.id == 'weekly_tokens');

      expect(window.limit, 1000);
      expect(window.percentUsed, 50);
      // Neither tool publishes an allowance, so this must never be dressed up
      // as a figure the provider blessed.
      expect(window.source, UsageSource.localTracking);
      expect(window.source.isProviderReported, isFalse);
      expect(
        data.notes.any((n) => n.contains('token budget')),
        isTrue,
      );
    });

    test('adopting it is a local link, not a connected account', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('glm-5.2')],
          active: _model('glm-5.2'),
        ),
      );
      final provider = build(reader);

      final result = await provider.enableLocalOnly();

      expect(result.status, ConnectionStatus.limited);
      // No key was involved, so a restart must not go looking for one.
      expect(result.usesStoredKey, isFalse);
    });

    test('survives a restart, because there is no key to lose', () async {
      final reader = _StubReader(
        reading: AgentUsageReading(
          models: [_model('glm-5.2')],
          active: _model('glm-5.2'),
        ),
      );
      await build(reader).enableLocalOnly();

      final restored = build(reader);
      await restored.restore();

      expect(restored.connection.status, ConnectionStatus.limited);
    });
  });

  group('nothing to report', () {
    test('says why rather than showing a zero', () async {
      final provider = build(_StubReader(
        reading: const AgentUsageReading.unavailable(
          'OpenCode has not been used in the last 7 days.',
        ),
      ));

      final data = await provider.fetchUsage(const AppSettings());

      expect(data.windows, isEmpty);
      expect(
        data.usageUnavailableReason,
        'OpenCode has not been used in the last 7 days.',
      );
    });

    test('offers steps instead of a Retry that cannot help', () async {
      final provider = build(_StubReader(
        reading: const AgentUsageReading.unavailable(
          'Kilo Code has not been used in the last 7 days.',
        ),
      ));

      final data = await provider.fetchUsage(const AppSettings());

      // Retrying re-reads the same empty record, so the card must not offer
      // it — the user pressed it repeatedly and nothing happened.
      expect(data.usageUnavailableIsPermanent, isTrue);
      expect(data.fixItSteps, isNotEmpty);
      expect(data.fixItSteps.first, contains('opencode'));
    });

    test('a tool that was never run cannot be added', () async {
      final provider = build(_StubReader(available: false));

      final result = await provider.enableLocalOnly();

      expect(result.status, ConnectionStatus.error);
      expect(result.message, contains('Run it once'));
    });
  });

  group('reading a real session database', () {
    test('is absent rather than wrong when there is no database', () async {
      final store = AgentSessionStore(
        databasePath: '${Directory.systemTemp.path}/nothing-here.db',
        displayName: 'OpenCode',
      );

      expect(store.isAvailable, isFalse);
      expect((await store.read()).hasUsage, isFalse);
    });
  });

  group('Hermes reports through its own commands', () {
    test('reads the models table out of the insights report', () {
      // The report as Hermes actually prints it.
      const report = '''
  📊 Hermes Insights

  📋 Overview
  ────────────────────────────
  Sessions:          37            Messages:        112
  Input tokens:      493,848       Output tokens:   15,134

  🤖 Models Used
  ────────────────────────────
  Model                          Sessions       Tokens
  hy3:free                             33      919,926
  glm-4.6                               4       12,004

  📱 Platforms
  ────────────────────────────
  cli                  33        104
''';

      final models = HermesInsightsSource.parseInsights(report);

      expect(models.map((m) => m.model), ['hy3:free', 'glm-4.6']);
      expect(models.first.tokens, 919926);
      expect(models.first.sessions, 33);
      // The next section must not be swept in as a model.
      expect(models.any((m) => m.model == 'cli'), isFalse);
    });

    test('takes the current model from status, not from the busiest', () {
      const status = '''
◆ Environment
  Project:      /Users/someone/.hermes
  Model:        tencent/hy3:free
  Provider:     Nous Portal
''';

      expect(HermesInsightsSource.parseStatus(status), (
        'tencent/hy3:free',
        'Nous Portal',
      ));
    });

    test('a report it cannot read yields nothing, never a zero', () {
      expect(HermesInsightsSource.parseInsights('nothing like a report'), isEmpty);
      expect(HermesInsightsSource.parseStatus('no model here'), isNull);
    });
  });
}
