import 'dart:ui' show PointerDeviceKind;

import 'package:ai_usage_monitor/ui/rail/rail_settings_button.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpButton(
  WidgetTester tester, {
  required bool expanded,
  VoidCallback? onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.of(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: RailSettingsButton(
            railExpanded: expanded,
            onRightEdge: true,
            onPressed: onPressed ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double opacityOf(WidgetTester tester, Key key) =>
    tester.widget<Opacity>(find.byKey(key)).opacity;

void main() {
  testWidgets('reveals on rail open and folds after the delay', (tester) async {
    await pumpButton(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 400));

    expect(opacityOf(tester, RailSettingsButton.revealedKey), closeTo(1, 0.01));

    await tester.pump(RailSettingsButton.autoFoldDelay);
    await tester.pump(const Duration(milliseconds: 300));

    expect(opacityOf(tester, RailSettingsButton.revealedKey), closeTo(0, 0.01));
    expect(opacityOf(tester, RailSettingsButton.foldedKey), closeTo(1, 0.01));
  });

  testWidgets('manual hover keeps the gear revealed', (tester) async {
    await pumpButton(tester, expanded: true);
    await tester.pump(const Duration(milliseconds: 400));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(RailSettingsButton)),
    );
    await tester.pump();

    await tester.pump(RailSettingsButton.autoFoldDelay);
    await tester.pump(const Duration(seconds: 1));

    expect(opacityOf(tester, RailSettingsButton.revealedKey), closeTo(1, 0.01));

    await gesture.removePointer();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opacityOf(tester, RailSettingsButton.revealedKey), closeTo(0, 0.01));
  });

  testWidgets('tap opens settings when expanded', (tester) async {
    var tapped = false;
    await pumpButton(tester, expanded: true, onPressed: () => tapped = true);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(RailSettingsButton));

    expect(tapped, isTrue);
  });
}
