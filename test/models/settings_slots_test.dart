import 'package:ai_usage_monitor/models/app_settings.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rail's length has to be one number, agreed on in three places: this
/// default, [ProviderCatalog.slotCount], and `MainFlutterWindow.slotCount` on
/// the native side, which sizes the window the rail is drawn into.
///
/// They drifted once. The default here said four while the window was built for
/// three, so the rail rendered a position that had nowhere to go — a plus the
/// user could see but the window could not fit. Dart cannot express the
/// constraint directly, because a default parameter value must be const and
/// `List.filled` is not, so it is asserted here instead.
void main() {
  group('the rail is one length everywhere', () {
    test('the empty rail has one entry per slot', () {
      expect(AppSettings.emptySlots, hasLength(ProviderCatalog.slotCount));
    });

    test('a fresh settings object starts at that length', () {
      expect(const AppSettings().slots, hasLength(ProviderCatalog.slotCount));
    });

    test('settings stored by a build with more slots are truncated', () {
      // Preferences outlive the code that wrote them. The extra position is
      // dropped rather than carried into a rail that cannot draw it.
      final settings = AppSettings.fromJson({
        'slots': ['claude', 'chatgpt', 'opencode', 'antigravity'],
      });

      expect(settings.slots, hasLength(ProviderCatalog.slotCount));
      expect(settings.slots, ['claude', 'chatgpt', 'opencode']);
    });

    test('settings stored by a build with fewer slots are padded', () {
      final settings = AppSettings.fromJson({
        'slots': ['claude'],
      });

      expect(settings.slots, hasLength(ProviderCatalog.slotCount));
      expect(settings.slots.first, 'claude');
      expect(settings.slots.skip(1), everyElement(isNull));
    });
  });
}
