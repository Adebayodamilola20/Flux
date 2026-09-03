import 'dart:convert';
import 'dart:io';

import 'package:ai_usage_monitor/models/usage_source.dart';
import 'package:ai_usage_monitor/providers/claude/claude_live_source.dart';
import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Writes a `.claude/.credentials.json` under [home] with the given token, the
/// same shape Claude Code writes.
void writeCredentials(
  String home, {
  required String token,
  DateTime? expiresAt,
}) {
  final dir = Directory('$home/.claude')..createSync(recursive: true);
  File('${dir.path}/.credentials.json').writeAsStringSync(
    jsonEncode({
      'claudeAiOauth': {
        'accessToken': token,
        if (expiresAt != null)
          'expiresAt': expiresAt.millisecondsSinceEpoch,
      },
    }),
  );
}

/// A live usage body in the shape Anthropic's endpoint returns.
String liveBody({num fiveHour = 12, num sevenDay = 40}) {
  return jsonEncode({
    'five_hour': {
      'utilization': fiveHour,
      'resets_at': '2026-08-31T01:30:00.000000+00:00',
    },
    'seven_day': {
      'utilization': sevenDay,
      'resets_at': '2026-09-03T18:00:00.000000+00:00',
    },
  });
}

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('claude_live_test');
  });

  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  test('reports no credentials when Claude Code is not signed in', () async {
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(source.isAvailable, isFalse);
    final (reading, failure) = await source.fetch();
    expect(reading, isNull);
    expect(failure, ClaudeLiveFailure.noCredentials);
  });

  test('does not call the endpoint when the token has expired', () async {
    writeCredentials(
      home.path,
      token: 'stale',
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    var called = false;
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    final (reading, failure) = await source.fetch();

    // Never touched the network: refreshing would log the user out of their
    // own CLI, so an expired token means "use the cache", not "call anyway".
    expect(called, isFalse);
    expect(reading, isNull);
    expect(failure, ClaudeLiveFailure.tokenExpired);
  });

  test('sends the session token with the headers Anthropic expects', () async {
    writeCredentials(
      home.path,
      token: 'good-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    http.Request? captured;
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          liveBody(),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await source.fetch();

    expect(captured, isNotNull);
    expect(captured!.url, ClaudeLiveUsageSource.usageUrl);
    expect(captured!.headers['Authorization'], 'Bearer good-token');
    expect(captured!.headers['anthropic-beta'], 'oauth-2025-04-20');
  });

  test('parses the live utilization into percentage windows', () async {
    writeCredentials(
      home.path,
      token: 'good-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async => http.Response(liveBody(), 200)),
    );

    final (reading, failure) = await source.fetch();

    expect(failure, isNull);
    expect(reading, isNotNull);
    final session = reading!.windows.firstWhere((w) => w.id == 'five_hour');
    final week = reading.windows.firstWhere((w) => w.id == 'seven_day');
    expect(session.percentUsed, 12);
    expect(week.percentUsed, 40);
    expect(session.resetsAt, isNotNull);
    // These are Anthropic's own figures, fetched live.
    expect(session.source, UsageSource.officialApi);
  });

  test('handles the utilization arriving nested under a key', () async {
    writeCredentials(
      home.path,
      token: 'good-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'utilization': jsonDecode(liveBody())}),
          200,
        ),
      ),
    );

    final (reading, _) = await source.fetch();

    expect(reading, isNotNull);
    expect(reading!.windows, isNotEmpty);
  });

  test('surfaces a rejected token as unauthorized, not a cache miss', () async {
    writeCredentials(
      home.path,
      token: 'rejected',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async => http.Response('nope', 401)),
    );

    final (reading, failure) = await source.fetch();

    expect(reading, isNull);
    expect(failure, ClaudeLiveFailure.unauthorized);
  });

  test('reports a network failure when the request throws', () async {
    writeCredentials(
      home.path,
      token: 'good-token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final source = ClaudeLiveUsageSource(
      homeDirectory: home.path,
      client: MockClient((_) async => throw const SocketException('down')),
    );

    final (reading, failure) = await source.fetch();

    expect(reading, isNull);
    expect(failure, ClaudeLiveFailure.network);
  });

  group('where the session is found', () {
    /// The blob Claude Code stores in the login Keychain.
    String keychainBlob({required String token, DateTime? expiresAt}) {
      return jsonEncode({
        'claudeAiOauth': {
          'accessToken': token,
          if (expiresAt != null) 'expiresAt': expiresAt.millisecondsSinceEpoch,
        },
      });
    }

    test('uses the Keychain session when the stored file has expired', () async {
      // The state of a current Claude Code install: the old file is left behind
      // with a token that expired months ago, while the live session lives in
      // the Keychain. Reading the file alone is what made the rail fall back to
      // a cached figure on every single refresh.
      writeCredentials(
        home.path,
        token: 'stale-file-token',
        expiresAt: DateTime.now().subtract(const Duration(days: 60)),
      );

      String? sentAuthorization;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async => ClaudeCodeCredentialAccess.found(
          keychainBlob(
            token: 'live-keychain-token',
            expiresAt: DateTime.now().add(const Duration(hours: 6)),
          ),
        ),
        client: MockClient((request) async {
          sentAuthorization = request.headers['Authorization'];
          return http.Response(liveBody(fiveHour: 78), 200);
        }),
      );

      final (reading, failure) = await source.fetch();

      expect(failure, isNull);
      expect(sentAuthorization, 'Bearer live-keychain-token');
      expect(reading!.windows.first.consumed, 78);
      expect(reading.windows.first.source, UsageSource.officialApi);
    });

    test('falls back to the file when the Keychain has nothing', () async {
      writeCredentials(
        home.path,
        token: 'file-token',
        expiresAt: DateTime.now().add(const Duration(hours: 6)),
      );

      String? sentAuthorization;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async => const ClaudeCodeCredentialAccess.absent(),
        client: MockClient((request) async {
          sentAuthorization = request.headers['Authorization'];
          return http.Response(liveBody(), 200);
        }),
      );

      final (reading, failure) = await source.fetch();

      expect(failure, isNull);
      expect(sentAuthorization, 'Bearer file-token');
      expect(reading!.hasUsage, isTrue);
    });

    test('reports a declined Keychain prompt as its own reason', () async {
      // Nothing is broken and the account is fine — the user said no to a
      // system dialog. The provider shows cached figures and says why, rather
      // than reporting the account as signed out.
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async => const ClaudeCodeCredentialAccess.denied(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final (reading, failure) = await source.fetch();

      expect(reading, isNull);
      expect(failure, ClaudeLiveFailure.keychainDenied);
    });

    test('reads a Keychain blob stored without the outer wrapper', () async {
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async => ClaudeCodeCredentialAccess.found(
          jsonEncode({
            'accessToken': 'bare-token',
            'expiresAt':
                DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch,
          }),
        ),
        client: MockClient(
          (_) async => http.Response(liveBody(fiveHour: 91), 200),
        ),
      );

      final (reading, _) = await source.fetch();

      expect(reading!.windows.first.consumed, 91);
    });

    test('reads the Keychain once and reuses the token', () async {
      // Every read is an inter-process call that can raise an approval dialog.
      // Asking again on each thirty-second poll would put that dialog in front
      // of the user twice a minute.
      var keychainReads = 0;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async {
          keychainReads++;
          return ClaudeCodeCredentialAccess.found(
            keychainBlob(
              token: 'live',
              expiresAt: DateTime.now().add(const Duration(hours: 6)),
            ),
          );
        },
        client: MockClient((_) async => http.Response(liveBody(), 200)),
      );

      await source.fetch();
      await source.fetch();
      await source.fetch();

      expect(keychainReads, 1);
    });

    test('stops asking after the prompt is declined', () async {
      var keychainReads = 0;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async {
          keychainReads++;
          return const ClaudeCodeCredentialAccess.denied();
        },
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await source.fetch();
      await source.fetch();

      // "No" is an answer. Re-prompting on the next poll would make declining
      // impossible in practice.
      expect(keychainReads, 1);
      final (_, failure) = await source.fetch();
      expect(failure, ClaudeLiveFailure.keychainDenied);
    });

    test('asks again five minutes later, not half an hour', () async {
      // A refusal here is usually a mis-click or a dialog that landed at a bad
      // moment, and until it is granted the rail has nothing live to show. The
      // back-off has to be long enough that declining is possible and short
      // enough that changing your mind does not mean waiting out an afternoon.
      expect(
        ClaudeLiveUsageSource.keychainBackoff,
        const Duration(minutes: 5),
      );
    });

    test('and forgets the refusal entirely when the app is quit', () async {
      // Nothing about a refusal is written down: it lives on the source, which
      // dies with the process. Quitting is how a user stops being asked, and
      // it works because there is nothing to survive the quit. A fresh source
      // stands in for a fresh launch.
      var keychainReads = 0;
      ClaudeLiveUsageSource build() => ClaudeLiveUsageSource(
            homeDirectory: home.path,
            keychainReader: () async {
              keychainReads++;
              return const ClaudeCodeCredentialAccess.denied();
            },
            client: MockClient((_) async => http.Response('{}', 200)),
          );

      final first = build();
      await first.fetch();
      await first.fetch();
      expect(keychainReads, 1);

      await build().fetch();

      expect(keychainReads, 2);
    });

    test('asks again when the user deliberately refreshes', () async {
      var keychainReads = 0;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async {
          keychainReads++;
          return const ClaudeCodeCredentialAccess.denied();
        },
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await source.fetch();
      expect(keychainReads, 1);

      // Pressing Refresh means "I have just fixed this, try now" — it must not
      // sit out the back-off.
      source.reset();
      await source.fetch();

      expect(keychainReads, 2);
    });

    test('does not refresh an expired token from either store', () async {
      // Refreshing would rotate the token and sign the user out of their own
      // CLI. A stale number is recoverable; a broken login is not.
      var requests = 0;
      final source = ClaudeLiveUsageSource(
        homeDirectory: home.path,
        keychainReader: () async => ClaudeCodeCredentialAccess.found(
          keychainBlob(
            token: 'expired',
            expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ),
        client: MockClient((_) async {
          requests++;
          return http.Response(liveBody(), 200);
        }),
      );

      final (reading, failure) = await source.fetch();

      expect(reading, isNull);
      expect(failure, ClaudeLiveFailure.tokenExpired);
      expect(requests, 0);
    });

    group('signing in again', () {
      test('re-reads the session once the stored one is replaced', () async {
        // The complaint this fixes: `claude /login` as a different account,
        // and the rail goes on reporting the account that was left. The old
        // token has not expired, so nothing about it looks wrong — the only
        // evidence is that the item behind it was rewritten.
        var stamp = DateTime(2026, 8, 31, 9);
        var reads = 0;
        final tokens = ['first', 'second'];

        final source = ClaudeLiveUsageSource(
          homeDirectory: home.path,
          keychainStampReader: () async => stamp,
          keychainReader: () async {
            final token = tokens[reads.clamp(0, tokens.length - 1)];
            reads++;
            return ClaudeCodeCredentialAccess.found(
              keychainBlob(
                token: token,
                expiresAt: DateTime.now().add(const Duration(hours: 6)),
              ),
            );
          },
          client: MockClient((request) async {
            return http.Response(
              liveBody(
                fiveHour:
                    request.headers['Authorization'] == 'Bearer second' ? 3 : 78,
              ),
              200,
            );
          }),
        );

        final (before, _) = await source.fetch();
        expect(before!.windows.first.consumed, 78);
        expect(reads, 1);

        // Unchanged store: still one read, still the same account.
        await source.fetch();
        expect(reads, 1);

        // The user signs in again.
        stamp = DateTime(2026, 8, 31, 10);
        final (after, _) = await source.fetch();

        expect(reads, 2);
        expect(after!.windows.first.consumed, 3);
      });

      test('a new sign-in is asked about even after a refusal', () async {
        // The back-off exists so declining once is respected. It must not
        // outlive the thing it was an answer about: a user who declined, then
        // signed in again, is asking a different question.
        var stamp = DateTime(2026, 8, 31, 9);
        var reads = 0;

        final source = ClaudeLiveUsageSource(
          homeDirectory: home.path,
          keychainStampReader: () async => stamp,
          keychainReader: () async {
            reads++;
            return const ClaudeCodeCredentialAccess.denied();
          },
          client: MockClient((_) async => http.Response('{}', 200)),
        );

        await source.fetch();
        await source.fetch();
        expect(reads, 1, reason: 'the refusal is respected while nothing has '
            'changed');

        stamp = DateTime(2026, 8, 31, 10);
        await source.fetch();
        expect(reads, 2);
      });

      test('holds the token when the stamp cannot be read', () async {
        // No native stamp — an older build, say. The token is still reused, so
        // the poll costs one request rather than a Keychain round trip; the
        // hold is simply time-bounded instead of stamp-bounded.
        var reads = 0;
        final source = ClaudeLiveUsageSource(
          homeDirectory: home.path,
          keychainStampReader: () async => null,
          keychainReader: () async {
            reads++;
            return ClaudeCodeCredentialAccess.found(
              keychainBlob(
                token: 'live',
                expiresAt: DateTime.now().add(const Duration(hours: 6)),
              ),
            );
          },
          client: MockClient((_) async => http.Response(liveBody(), 200)),
        );

        await source.fetch();
        await source.fetch();

        expect(reads, 1);
      });
    });
  });
}
