import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/models/rail_placement.dart';
import 'package:ai_usage_monitor/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the rail follows the theme', () {
    test('is not black in both themes', () {
      // Reported as a bug: the theme was set to light, the card went light,
      // and the rail stayed a black bar. It was hard-coded black on the
      // reasoning that a hardware-like edge notch is not a themed panel —
      // true of the shape, not of the colour.
      expect(AppPalette.dark.railFill, isNot(AppPalette.light.railFill));
      expect(AppPalette.light.railFill.computeLuminance(), greaterThan(0.7));
      expect(AppPalette.dark.railFill.computeLuminance(), lessThan(0.1));
    });

    test('lerps between themes without dropping the rail colours', () {
      final AppPalette mixed = AppPalette.dark.lerp(AppPalette.light, 1.0);
      expect(mixed.railFill, AppPalette.light.railFill);
      expect(mixed.railBorder, AppPalette.light.railBorder);
    });
  });

  group('rail surface', () {
    test('defaults to solid', () {
      expect(const AppSettings().railAppearance, RailAppearance.solid);
    });

    test('survives a round trip through storage', () {
      final saved = const AppSettings()
          .copyWith(railAppearance: RailAppearance.glass)
          .toJson();

      expect(
        AppSettings.fromJson(saved).railAppearance,
        RailAppearance.glass,
      );
    });

    test('falls back to solid on an unreadable value', () {
      expect(
        AppSettings.fromJson(const {'railAppearance': 'frosted-ish'})
            .railAppearance,
        RailAppearance.solid,
      );
    });
  });
}
