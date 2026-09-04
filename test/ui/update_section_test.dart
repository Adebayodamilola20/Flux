import 'package:ai_usage_monitor/services/native/native_bridge.dart';
import 'package:ai_usage_monitor/services/update_checker.dart';
import 'package:ai_usage_monitor/ui/panel/update_section.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/fake_native_bridge.dart';

const _manifest =
    '{"version":"1.0.0","build":"202609041500",'
    '"url":"https://example.com/DevNotch-1.0.0.dmg","notes":"Faster refresh"}';

void main() {
  late FakeNativeBridge native;

  setUp(() => native = FakeNativeBridge());
  tearDown(() => native.dispose());

  Future<UpdateChecker> pump(WidgetTester tester, {String installed = ''}) async {
    final checker = UpdateChecker(
      installedBuild: installed,
      manifestUrl: Uri.parse('https://example.com/latest.json'),
      client: MockClient((_) async => http.Response(_manifest, 200)),
    );
    addTearDown(checker.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<NativeBridge>.value(value: native),
          ChangeNotifierProvider<UpdateChecker>.value(value: checker),
        ],
        child: MaterialApp(
          theme: AppTheme.of(Brightness.dark),
          home: const Scaffold(
            body: SizedBox(
              width: 600,
              child: UpdateSection(version: '1.0.0'),
            ),
          ),
        ),
      ),
    );
    return checker;
  }

  testWidgets('shows the installed version and a way to check', (tester) async {
    await pump(tester);

    expect(find.text('DevNotch 1.0.0'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('offers the download once a newer build is published',
      (tester) async {
    final checker = await pump(tester, installed: '202609041400');

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(checker.available, isNotNull);
    expect(find.text('DevNotch 1.0.0 is available'), findsOneWidget);
    expect(find.text('Faster refresh'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(native.openedUrls, ['https://example.com/DevNotch-1.0.0.dmg']);
  });
}
