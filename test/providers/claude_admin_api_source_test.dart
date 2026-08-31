import 'dart:convert';

import 'package:ai_usage_monitor/models/usage_failure.dart';
import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_admin_api_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ClaudeAdminApiSource sourceReturning(
  int status,
  Object body, {
  void Function(http.Request)? inspect,
}) {
  final client = MockClient((request) async {
    inspect?.call(request);
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
  return ClaudeAdminApiSource(client: client);
}

void main() {
  group('request', () {
    test('targets the documented usage report endpoint with auth headers',
        () async {
      http.Request? captured;
      final source = sourceReturning(
        200,
        {
          'data': [
            {
              'ending_at': '2026-06-15T23:59:59Z',
              'results': [
                {'uncached_input_tokens': 1, 'output_tokens': 1},
              ],
            },
          ],
        },
        inspect: (r) => captured = r,
      );

      await source.fetchDailyUsage(adminKey: 'sk-ant-admin-test');

      expect(captured!.url.host, 'api.anthropic.com');
      expect(captured!.url.path, '/v1/organizations/usage_report/messages');
      expect(captured!.url.queryParameters['bucket_width'], '1d');
      expect(captured!.headers['x-api-key'], 'sk-ant-admin-test');
      expect(captured!.headers['anthropic-version'], '2023-06-01');
    });
  });

  group('successful parsing', () {
    test('sums every token category across buckets and results', () async {
      final source = sourceReturning(200, {
        'data': [
          {
            'ending_at': '2026-06-15T23:59:59Z',
            'results': [
              {
                'uncached_input_tokens': 100,
                'cache_read_input_tokens': 50,
                'output_tokens': 25,
                'cache_creation': {
                  'ephemeral_5m_input_tokens': 10,
                  'ephemeral_1h_input_tokens': 5,
                },
              },
              {'uncached_input_tokens': 10, 'output_tokens': 0},
            ],
          },
        ],
      });

      final window = await source.fetchDailyUsage(adminKey: 'k');

      expect(window, isNotNull);
      expect(window!.consumed, 200);
      expect(window.source, UsageSource.officialApi);
      expect(window.limit, isNull,
          reason: 'the report gives consumption, not a quota');
      expect(window.percentUsed, isNull);
      expect(window.resetsAt, isNotNull);
    });

    test('supports the flat cache-creation field', () async {
      final source = sourceReturning(200, {
        'data': [
          {
            'results': [
              {
                'input_tokens': 10,
                'cache_creation_input_tokens': 90,
              },
            ],
          },
        ],
      });

      final window = await source.fetchDailyUsage(adminKey: 'k');
      expect(window!.consumed, 100);
    });

    test('returns null when the report has no buckets', () async {
      final source = sourceReturning(200, {'data': []});
      expect(await source.fetchDailyUsage(adminKey: 'k'), isNull);
    });
  });

  group('failures', () {
    Future<UsageFailure> failureFrom(ClaudeAdminApiSource source) async {
      try {
        await source.fetchDailyUsage(adminKey: 'k');
        fail('expected a UsageFailure');
      } on UsageFailure catch (e) {
        return e;
      }
    }

    test('maps 401 to an authentication failure that is not auto-retried',
        () async {
      final failure = await failureFrom(sourceReturning(401, {}));
      expect(failure.kind, UsageFailureKind.authentication);
      expect(failure.isRetryable, isFalse);
      expect(failure.hint, isNotNull);
    });

    test('maps 403 to an authentication failure', () async {
      final failure = await failureFrom(sourceReturning(403, {}));
      expect(failure.kind, UsageFailureKind.authentication);
    });

    test('maps 429 to a retryable rate-limit failure', () async {
      final failure = await failureFrom(sourceReturning(429, {}));
      expect(failure.kind, UsageFailureKind.rateLimited);
      expect(failure.isRetryable, isTrue);
    });

    test('maps 500 to a generic retryable failure', () async {
      final failure = await failureFrom(sourceReturning(500, {}));
      expect(failure.kind, UsageFailureKind.unknown);
      expect(failure.message, contains('500'));
    });

    test('reports a transport error as a network failure', () async {
      final source = ClaudeAdminApiSource(
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );
      final failure = await failureFrom(source);
      expect(failure.kind, UsageFailureKind.network);
    });

    test('refuses to report a number from an unrecognised schema', () async {
      final source = sourceReturning(200, {
        'data': [
          {
            'results': [
              {'some_future_field': 42},
            ],
          },
        ],
      });

      final failure = await failureFrom(source);
      expect(failure.kind, UsageFailureKind.unknown);
      expect(
        failure.message,
        contains('not recognised'),
        reason: 'reporting zero would be indistinguishable from real zero usage',
      );
    });

    test('rejects a non-JSON body', () async {
      final failure = await failureFrom(sourceReturning(200, '<html>oops'));
      expect(failure.kind, UsageFailureKind.unknown);
    });

    test('never puts the key in a failure message', () async {
      final failure = await failureFrom(sourceReturning(401, {}));
      expect(failure.message, isNot(contains('sk-ant')));
      expect(failure.hint, isNot(contains('sk-ant')));
    });
  });
}

/// Stand-in for a transport-level error, avoiding a dart:io import in a test
/// that otherwise runs anywhere.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
