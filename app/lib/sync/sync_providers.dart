import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'api_client.dart';
import 'device_session.dart';
import 'sync_service.dart';

final deviceSessionProvider = Provider<DeviceSession>((_) => DeviceSession());

/// The device token, or null when this phone has never been paired.
///
/// A `FutureProvider` rather than a synchronous read because the token lives
/// in the Keystore and reading it is genuinely asynchronous. Every screen that
/// shows a cloud feature waits on this, so a cold start never briefly offers
/// "connect" to a phone that is already connected.
final deviceTokenProvider = FutureProvider<String?>((ref) async {
  return ref.watch(deviceSessionProvider).token();
});

final apiClientProvider = Provider<ApiClient?>((ref) {
  if (!ApiConfig.isConfigured) return null;
  final token = ref.watch(deviceTokenProvider).value;
  if (token == null) return null;
  final client = ApiClient(token: token);
  ref.onDispose(client.close);
  return client;
});

final syncServiceProvider = Provider<SyncService?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  final svc = SyncService(ref.watch(repositoryProvider), api);
  ref.onDispose(svc.stop);
  return svc;
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final svc = ref.watch(syncServiceProvider);
  if (svc == null) return const Stream.empty();
  return svc.status.startWithValue(svc.last);
});

/// Runs for the app's lifetime once a device is paired.
///
/// Four triggers, and each earns its place:
///
///   - a local write, debounced, so a burst of captured messages is one push;
///   - connectivity returning, because the common case is a phone that was in
///     a pocket in a basement bazaar and has ten entries waiting;
///   - the app coming back to the foreground, when the numbers must be fresh;
///   - a five-minute tick while the app is open, which is how a portal edit
///     reaches the phone. Push notifications would be better and are the
///     backlog item; polling every five minutes costs one request and is
///     honest about being a poll.
final syncRunnerProvider = Provider<void>((ref) {
  final svc = ref.watch(syncServiceProvider);
  if (svc == null) return;

  unawaited(svc.syncNow());

  final subs = <StreamSubscription>[
    ref.read(repositoryProvider).db.tableUpdates().listen((_) {
      svc.scheduleSync(const Duration(seconds: 3));
    }),
    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        svc.scheduleSync(const Duration(seconds: 1));
      }
    }),
  ];
  final poll = Timer.periodic(const Duration(minutes: 5), (_) => svc.scheduleSync(Duration.zero));

  // Coming back to the app is the moment the agent looks at the numbers, so
  // it is the moment they must be fresh — whatever the other phones did in
  // the meantime.
  final lifecycle = AppLifecycleListener(onResume: () => svc.scheduleSync(const Duration(milliseconds: 500)));

  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
    poll.cancel();
    lifecycle.dispose();
  });
});

extension<T> on Stream<T> {
  Stream<T> startWithValue(T v) async* {
    yield v;
    yield* this;
  }
}
