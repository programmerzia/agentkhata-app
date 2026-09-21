import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../features/widget/home_widget_sync.dart';
import '../sync/sync_providers.dart';
import 'queue_processor.dart';

/// Capture with the app closed.
///
/// Runs inside the headless engine that BackgroundEngine.kt starts when an
/// operator message arrives and no UI is listening. It does exactly what the
/// open app would: parse the queued messages into the books, push them to the
/// shop, pull what the other phones sent, and refresh the home-screen widget —
/// so the entry is in the portal, and on the widget, within seconds of the
/// notification, whether or not anyone has opened the app today.
///
/// The same providers as the UI build the same services, so there is one
/// implementation of every step and nothing here to drift.
Future<void> runBackgroundCapture() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final container = ProviderContainer();
  // Kept alive for the engine's life so the widget follows every capture.
  container.listen(homeWidgetSyncProvider, (_, _) {}, fireImmediately: true);

  var running = false;
  var again = false;

  Future<void> run() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        await processCaptureQueue(container.read(ingestionProvider));
        await container.read(deviceTokenProvider.future);
        await container.read(syncServiceProvider)?.syncNow();
      } while (again);
    } catch (error, stack) {
      debugPrint('background capture failed: $error\n$stack');
    } finally {
      running = false;
    }
  }

  const MethodChannel('no.osilion.agentkhata/background').setMethodCallHandler((call) async {
    if (call.method == 'process') unawaited(run());
    return null;
  });

  await run();
}
