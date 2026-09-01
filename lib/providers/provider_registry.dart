import 'provider_catalog.dart';
import 'usage_provider.dart';

/// Every provider this build ships with.
///
/// Not a rail: there is no fixed count here, because the number of providers
/// the app can measure and the number of positions the rail draws are separate
/// facts. The rail has [ProviderCatalog.slotCount] positions and the user
/// decides which providers go in them; the registry just holds all of them so
/// the picker has something to offer and the controller has something to poll.
class ProviderRegistry {
  ProviderRegistry(List<UsageProvider> providers)
    : assert(
        providers.length >= ProviderCatalog.slotCount,
        'The rail has ${ProviderCatalog.slotCount} positions, so there must be '
        'at least that many providers to fill them; got ${providers.length}',
      ),
      assert(
        providers.map((p) => p.id).toSet().length == providers.length,
        'Provider ids must be unique',
      ),
      _providers = List.unmodifiable(providers);

  final List<UsageProvider> _providers;

  List<UsageProvider> get all => _providers;

  /// The provider whose usage drives the menu-bar fallback and the rail's
  /// summary. Always the first slot.
  UsageProvider get primary => _providers.first;

  /// Slots with a working integration in this build.
  Iterable<UsageProvider> get implemented =>
      _providers.where((p) => p.descriptor.isImplemented);

  UsageProvider? byId(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Loads every stored connection. Called once at startup.
  Future<void> restoreAll() async {
    await Future.wait(_providers.map((p) => p.restore()));
  }

  Future<void> disposeAll() async {
    for (final p in _providers) {
      await p.dispose();
    }
  }
}
