import 'dart:async';

/// Several change signals as one stream, for the single listener that
/// subscribes to a provider's [changes].
///
/// Hand-rolled rather than pulling in a package for one merge. The sources
/// are infinite polling loops, so cancelling has to reach every one of them
/// or they keep statting files after the provider is gone.
Stream<void> mergeStreams(List<Stream<Object?>> sources) {
  final subscriptions = <StreamSubscription<Object?>>[];
  late final StreamController<void> controller;

  controller = StreamController<void>(
    onListen: () {
      for (final source in sources) {
        subscriptions.add(
          source.listen(
            (_) => controller.add(null),
            onError: controller.addError,
          ),
        );
      }
    },
    onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    },
  );

  return controller.stream;
}
