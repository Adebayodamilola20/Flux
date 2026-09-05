import 'package:ai_usage_monitor/providers/antigravity/antigravity_local_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// A quota summary in the shape the language server answers with.
String body({double gemini = 0.4, double claude = 1.0, String? reset}) => '''
{"response":{"groups":[
  {"displayName":"Gemini models","buckets":[
    {"bucketId":"gemini","displayName":"Weekly Limit Remaining",
     "remainingFraction":$gemini${reset == null ? '' : ',"resetTime":"$reset"'}}]},
  {"displayName":"Claude and GPT models","buckets":[
    {"bucketId":"byok","displayName":"Weekly Limit Remaining",
     "remainingFraction":$claude}]}
]}}''';

void main() {
  group('reading the quota summary', () {
    // The server reports what is left; every figure in this app is what has
    // been spent, so the fraction is inverted on the way in.
    test('reports what has been used, not what remains', () {
      final windows = AntigravityLocalServer.parseWindows(body());

      expect(windows, hasLength(2));
      expect(windows.first.consumed, 60);
      expect(windows.first.label, 'Gemini models');
      expect(windows.last.consumed, 0);
    });

    test('carries the reset time when the server names one', () {
      final windows = AntigravityLocalServer.parseWindows(
        body(reset: '2026-09-12T00:00:00Z'),
      );

      expect(windows.first.resetsAt, isNotNull);
    });

    test('stamps every window, so an old one can read as old', () {
      final windows = AntigravityLocalServer.parseWindows(body());

      expect(windows.every((w) => w.observedAt != null), isTrue);
    });

    test('drops a bucket with no usable fraction rather than guessing', () {
      const missing =
          '{"response":{"groups":[{"displayName":"Gemini models",'
          '"buckets":[{"bucketId":"g","remainingFraction":null},'
          '{"bucketId":"h","remainingFraction":1.4}]}]}}';

      expect(AntigravityLocalServer.parseWindows(missing), isEmpty);
    });

    test('says nothing at all rather than throwing on rubbish', () {
      expect(AntigravityLocalServer.parseWindows('not json'), isEmpty);
      expect(AntigravityLocalServer.parseWindows('[]'), isEmpty);
      expect(AntigravityLocalServer.parseWindows('{"response":{}}'), isEmpty);
    });
  });

  group('finding the server', () {
    test('takes the token from the command line, either spelling', () {
      const spaced = '900 /x/language_server --csrf_token abc123 --port 0';
      const equals = '900 /x/language_server --csrf_token=abc123';

      expect(AntigravityLocalServer.flagValue('--csrf_token', spaced), 'abc123');
      expect(AntigravityLocalServer.flagValue('--csrf_token', equals), 'abc123');
      expect(AntigravityLocalServer.flagValue('--nope', spaced), isNull);
    });

    test('reads every listening port, since only one of them answers', () {
      // The server opens more than one and does not say which serves the RPC.
      const lsof = '''
COMMAND   PID    USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
language_ 900 macmini   21u  IPv4  0x1      0t0  TCP 127.0.0.1:52001 (LISTEN)
language_ 900 macmini   23u  IPv4  0x2      0t0  TCP 127.0.0.1:52002 (LISTEN)
language_ 900 macmini   25u  IPv4  0x3      0t0  TCP 127.0.0.1:52001 (LISTEN)
''';

      expect(AntigravityLocalServer.parsePorts(lsof), [52001, 52002]);
    });

    test('finds no ports in output that lists none', () {
      expect(AntigravityLocalServer.parsePorts('COMMAND PID USER\n'), isEmpty);
    });
  });
}
