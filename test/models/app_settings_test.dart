import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings', () {
    test('round-trips through JSON', () {
      const settings = AppSettings(
        refreshInterval: Duration(minutes: 15),
        launchAtLogin: true,
        showMenuBarPercent: false,
        showMenuBarIcon: true,
        recordHistory: false,
        sessionTokenBudget: 123,
        weeklyTokenBudget: 456,
      );

      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('falls back to defaults for missing fields', () {
      final restored = AppSettings.fromJson(const {});
      expect(restored, const AppSettings());
    });

    test('rejects a refresh interval that would hammer the provider', () {
      final restored =
          AppSettings.fromJson(const {'refreshIntervalSeconds': 1});
      expect(restored.refreshInterval, const AppSettings().refreshInterval);
    });

    test('rejects non-positive token budgets', () {
      final restored = AppSettings.fromJson(const {
        'sessionTokenBudget': 0,
        'weeklyTokenBudget': -10,
      });
      expect(
        restored.sessionTokenBudget,
        AppSettings.defaultSessionTokenBudget,
      );
      expect(restored.weeklyTokenBudget, AppSettings.defaultWeeklyTokenBudget);
    });

    test('keeps the icon visible when the percentage is hidden', () {
      const hidden = AppSettings(
        showMenuBarIcon: false,
        showMenuBarPercent: false,
      );
      expect(
        hidden.effectiveShowMenuBarIcon,
        isTrue,
        reason: 'the menu bar item must never render as empty',
      );
    });

    test('respects a hidden icon while the percentage is shown', () {
      const settings = AppSettings(
        showMenuBarIcon: false,
        showMenuBarPercent: true,
      );
      expect(settings.effectiveShowMenuBarIcon, isFalse);
    });

    test('copyWith leaves untouched fields alone', () {
      const original = AppSettings(sessionTokenBudget: 42);
      final updated = original.copyWith(launchAtLogin: true);
      expect(updated.sessionTokenBudget, 42);
      expect(updated.launchAtLogin, isTrue);
    });
  });
}
