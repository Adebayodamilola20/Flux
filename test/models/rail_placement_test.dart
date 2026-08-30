import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/rail_placement.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RailEdge', () {
    test('defaults to the right edge', () {
      expect(const AppSettings().railEdge, RailEdge.right);
    });

    test('knows its opposite', () {
      expect(RailEdge.right.opposite, RailEdge.left);
      expect(RailEdge.left.opposite, RailEdge.right);
    });
  });

  group('RailExpansion', () {
    test('hover is the default and collapses on its own', () {
      const settings = AppSettings();
      expect(settings.railExpansion, RailExpansion.onHover);
      expect(settings.railExpansion.expandsOnHover, isTrue);
      expect(settings.railExpansion.autoCollapses, isTrue);
    });

    test('always-expanded never auto-collapses', () {
      expect(RailExpansion.alwaysExpanded.autoCollapses, isFalse);
      expect(RailExpansion.alwaysExpanded.expandsOnHover, isFalse);
    });

    test('click-to-open still collapses when dismissed', () {
      expect(RailExpansion.onClick.autoCollapses, isTrue);
      expect(RailExpansion.onClick.expandsOnHover, isFalse);
    });
  });

  group('RailOffset', () {
    test('centres by default', () {
      expect(const AppSettings().railOffset, RailOffset.centered);
      expect(RailOffset.centered.fraction, 0.5);
    });

    test('keeps the rail away from the very edge of the screen', () {
      // A rail flush against the top or bottom would be half off-screen.
      expect(const RailOffset(0).clamped(), 0.05);
      expect(const RailOffset(1).clamped(), 0.95);
      expect(const RailOffset(0.3).clamped(), 0.3);
    });
  });

  group('AppSettings rail persistence', () {
    test('round-trips every rail field', () {
      const settings = AppSettings(
        railEdge: RailEdge.left,
        railOffset: RailOffset(0.2),
        railExpansion: RailExpansion.alwaysExpanded,
        railVisible: false,
        screenId: 'display-7',
        themeMode: ThemeMode.dark,
        onboardingComplete: true,
      );

      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('falls back to defaults for an unrecognised stored value', () {
      final restored = AppSettings.fromJson(const {
        'railEdge': 'diagonal',
        'railExpansion': 'telepathy',
        'railOffset': 12.0,
        'themeMode': 'sepia',
      });

      expect(restored.railEdge, RailEdge.right);
      expect(restored.railExpansion, RailExpansion.onHover);
      expect(restored.railOffset, RailOffset.centered);
      expect(restored.themeMode, ThemeMode.system);
    });

    test('clearScreenId forgets the remembered monitor', () {
      const settings = AppSettings(screenId: 'display-7');
      expect(settings.copyWith(clearScreenId: true).screenId, isNull);
      expect(settings.copyWith().screenId, 'display-7');
    });
  });
}
