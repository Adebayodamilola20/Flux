import 'provider_catalog.dart';
import 'usage_provider.dart';

/// The three providers this build ships with, in rail order.
///
/// The count is fixed at [ProviderCatalog.slotCount] and checked here, because
/// the rail's layout is designed around exactly three rings. A build that wired
/// up two or four would render wrong in a way that is much harder to
/// diagnose than an assertion at startup.
class ProviderRegistry {
  ProviderRegistry(List<UsageProvider> providers)
    : assert(
        providers.length == ProviderCatalog.slotCount,
        'Expected exactly ${ProviderCatalog.slotCount} provider slots, '
        'got ${providers.length}',
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
