import 'dart:io';

import 'package:ai_usage_monitor/providers/agent/agent_session_store.dart';
import 'package:ai_usage_monitor/providers/agent/hermes_insights_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('devnotch-agent-'));
  tearDown(() => home.deleteSync(recursive: true));

  File write(String name, {required DateTime modifiedAt}) =>
      File('${home.path}/$name')
        ..writeAsStringSync('{}')
        ..setLastModifiedSync(modifiedAt);

  group('a sign-in counts as a change', () {
    // Account switches must reach the rail without the user opening the tool.
    // The stores are polled for "did anything change", so the sign-in file has
    // to be part of that answer, not only the session record.
    test('for OpenCode and Kilo Code', () {
      final now = DateTime.now();
      write('sessions.db', modifiedAt: now.subtract(const Duration(hours: 1)));
      write('auth.json', modifiedAt: now.subtract(const Duration(minutes: 1)));

      final store = AgentSessionStore(
        databasePath: '${home.path}/sessions.db',
        authPath: '${home.path}/auth.json',
        displayName: 'OpenCode',
      );

      expect(
        store.changedAt!.isAfter(now.subtract(const Duration(minutes: 2))),
        isTrue,
        reason: 'the newer sign-in wins over the older session record',
      );
    });

    test('for Hermes', () {
      final now = DateTime.now();
      Directory('${home.path}/sessions').createSync();
      // Later than anything the sessions directory can say, since it was
      // created just now.
      write('auth.json', modifiedAt: now.add(const Duration(hours: 1)));

      final source = HermesInsightsSource(
        executable: '${home.path}/hermes',
        sessionsDirectory: '${home.path}/sessions',
        authPath: '${home.path}/auth.json',
      );

      expect(
        source.changedAt!.isAfter(now.add(const Duration(minutes: 30))),
        isTrue,
      );
    });

    test('a missing sign-in file is simply not counted', () {
      final now = DateTime.now();
      write('sessions.db', modifiedAt: now.subtract(const Duration(hours: 1)));

      final store = AgentSessionStore(
        databasePath: '${home.path}/sessions.db',
        authPath: '${home.path}/nope.json',
        displayName: 'Kilo Code',
      );

      expect(store.changedAt, isNotNull);
      expect(AgentSessionStore.newestOf(['${home.path}/nope.json']), isNull);
    });
  });
}
