import 'package:ai_usage_monitor/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String manifest({
  String version = '1.0.0',
  String build = '202609041500',
  String url = 'https://example.com/DevNotch-1.0.0.dmg',
  String? notes,
}) =>
    '{"version":"$version","build":"$build","url":"$url"'
    '${notes == null ? '' : ',"notes":"$notes"'}}';

void main() {
  UpdateChecker checker(
    http.Client client, {
    String installed = '202609041400',
  }) =>
      UpdateChecker(
        installedBuild: installed,
        manifestUrl: Uri.parse('https://example.com/latest.json'),
        client: client,
      );

  group('reading the manifest', () {
    test('accepts the fields the packaging script writes', () {
      final info = UpdateInfo.parse(manifest(notes: 'Faster refresh'));

      expect(info, isNotNull);
      expect(info!.version, '1.0.0');
      expect(info.build, '202609041500');
      expect(info.downloadUrl.host, 'example.com');
      expect(info.notes, 'Faster refresh');
    });

    test('ignores anything it cannot read rather than guessing', () {
      expect(UpdateInfo.parse('not json'), isNull);
      expect(UpdateInfo.parse('[]'), isNull);
      expect(UpdateInfo.parse(manifest(build: '1.0.1')), isNull);
      expect(UpdateInfo.parse(manifest(url: 'DevNotch.dmg')), isNull);
    });
  });

  group('what counts as newer', () {
    // The marketing version stays at 1.0.0 while the asset is replaced in
    // place, so only the build stamp can tell two downloads apart.
    test('a later build stamp', () async {
      final c = checker(MockClient((_) async => http.Response(manifest(), 200)));

      final update = await c.check();

      expect(update, isNotNull);
      expect(c.available, same(update));
      expect(c.lastError, isNull);
    });

    test('not the same build, and not an older one', () async {
      final same = checker(
        MockClient((_) async => http.Response(manifest(), 200)),
        installed: '202609041500',
      );
      final older = checker(
        MockClient((_) async => http.Response(manifest(), 200)),
        installed: '202609049999',
      );

      expect(await same.check(), isNull);
      expect(await older.check(), isNull);
    });

    test('a developer run is never out of date', () async {
      // `flutter run` compiles no stamp. Nagging the developer to download
      // the build they are working on would be absurd.
      final c = checker(
        MockClient((_) async => http.Response(manifest(), 200)),
        installed: '',
      );

      expect(await c.check(), isNull);
    });
  });

  group('when the check cannot be made', () {
    test('an offline Mac keeps what it knows and says so', () async {
      final c = checker(MockClient((_) async => throw Exception('offline')));

      expect(await c.check(), isNull);
      expect(c.lastError, contains('reach'));
      expect(c.lastChecked, isNotNull);
    });

    test('a server error is reported, not treated as up to date', () async {
      final c = checker(MockClient((_) async => http.Response('', 503)));

      await c.check();

      expect(c.lastError, contains('503'));
    });

    test('a previous answer survives a failed re-check', () async {
      var fail = false;
      final c = checker(MockClient((_) async {
        if (fail) throw Exception('offline');
        return http.Response(manifest(), 200);
      }));

      await c.check();
      fail = true;
      await c.check();

      expect(c.available, isNotNull);
    });
  });
}
