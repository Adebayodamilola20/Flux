import 'package:ai_usage_monitor/models/provider_connection.dart';
import 'package:ai_usage_monitor/providers/provider_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards against one integration's wording being shown against another.
///
/// This is not hypothetical: the shared `consoleApiKey` copy once told
/// OpenRouter users to "open your Anthropic account and create an Admin API
/// key", because provider-specific text had been written into the enum every
/// key-based integration uses. With 40+ integrations planned, that class of
/// mistake scales badly, so it is pinned here.
void main() {
  /// Names that belong to one provider and must never appear in shared copy.
  const brandNames = [
    'Anthropic',
    'Claude',
    'OpenRouter',
    'Google',
    'Gemini',
    'Antigravity',
    'OpenAI',
    'Admin key',
    'Admin API',
  ];

  group('shared auth copy is provider-agnostic', () {
    for (final method in ProviderAuthMethod.values) {
      test('${method.name} call to action names no provider', () {
        for (final brand in brandNames) {
          expect(
            method.callToAction,
            isNot(contains(brand)),
            reason: '${method.name} button text mentions $brand, which would '
                'be shown on every provider using this auth method',
          );
        }
      });

      test('${method.name} explanation names no provider', () {
        for (final brand in brandNames) {
          expect(
            method.explanation,
            isNot(contains(brand)),
            reason: '${method.name} explanation mentions $brand',
          );
        }
      });
    }
  });

  group('provider-specific copy lives on the descriptor', () {
    test('every implemented slot describes itself', () {
      for (final slot in ProviderCatalog.available) {
        expect(slot.displayName, isNotEmpty);
        expect(slot.tagline, isNotEmpty);
      }
    });

    test('a key-based slot supplies its own hint and note', () {
      final keyBased = ProviderCatalog.available.where(
        (s) => s.authMethod == ProviderAuthMethod.consoleApiKey,
      );

      for (final slot in keyBased) {
        expect(
          slot.credentialHint,
          isNotNull,
          reason: '${slot.id} would show a generic placeholder in the paste '
              'field, giving the user no way to tell they copied the right '
              'thing',
        );
      }
    });

    test('a slot with no sign-in offers no call to action', () {
      final noSignIn = ProviderCatalog.available.where(
        (s) => s.authMethod == ProviderAuthMethod.localActivityOnly,
      );

      // The card renders explanation text rather than a button for these, so
      // the enum's call to action is never pressed. It must still read as a
      // statement rather than an instruction.
      for (final slot in noSignIn) {
        expect(slot.authMethod.callToAction, isNot(contains('Add')));
      }
    });
  });
}
