import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/providers.dart';
import 'capture/background.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'l10n/strings.dart';
import 'features/lock/app_lock.dart';
import 'features/widget/home_widget_sync.dart';
import 'sync/sync_providers.dart';

/// The headless engine's entry point: capture with the app closed.
///
/// Here rather than in its own library because the native side starts it by
/// name from the root library, and a function the compiler cannot see being
/// called is tree-shaken away without the pragma.
@pragma('vm:entry-point')
Future<void> backgroundMain() => runBackgroundCapture();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bangla month and weekday names. Without this, a date formatted in 'bn'
  // throws the first time a list with a date header is opened.
  await initializeDateFormatting();
  runApp(const ProviderScope(child: AgentKhataApp()));
}

class AgentKhataApp extends ConsumerWidget {
  const AgentKhataApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wait for preferences so the first frame already knows the language and
    // whether onboarding is done. One frame of the wrong language is a flash
    // every cold start, on the screen an agent opens forty times a day.
    final prefs = ref.watch(prefsProvider);
    if (prefs.isLoading) {
      return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }

    ref.watch(messageListenerProvider);
    ref.watch(syncRunnerProvider);
    // Watched at the root so the launcher widget keeps up with entries that
    // land while the agent is on some other screen, or on no screen at all.
    ref.watch(homeWidgetSyncProvider);
    ref.watch(homeWidgetRouteProvider);

    ref.read(repositoryProvider)
      ..ensureCashWallet()
      ..seedDefaultRulesIfEmpty();

    return MaterialApp.router(
      title: ref.s('app'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      /*
       * The lock wraps everything the router renders rather than sitting
       * inside a route: a shutter a deep link could route around is not a
       * shutter, and the pairing deep link is exactly such a link.
       */
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
