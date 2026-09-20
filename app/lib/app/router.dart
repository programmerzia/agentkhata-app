import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/customers/customers_screen.dart';
import '../features/devtools/message_simulator.dart';
import '../features/dayclose/dayclose_screen.dart';
import '../features/help/help_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/add_transaction_screen.dart';
import '../features/transactions/transactions_screen.dart';
import '../features/transactions/unsorted_screen.dart';
import '../l10n/strings.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ref.watch(onboardedProvider);
  return GoRouter(
    initialLocation: onboarded ? '/' : '/onboarding',
    redirect: (_, state) {
      /*
       * Onboarding is the only gate, and connecting to CoreBari is not one.
       * An agent installs this app at a counter with a customer waiting; it
       * has to work offline, immediately, with no account. The cloud is
       * something they turn on later from Settings, when they want the portal
       * or a second phone.
       */
      if (!ref.read(onboardedProvider) && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/add', builder: (_, s) => AddTransactionScreen(presetType: s.uri.queryParameters['type'], customerId: s.uri.queryParameters['customer'])),
      GoRoute(path: '/unsorted', builder: (_, _) => const UnsortedScreen()),
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      GoRoute(path: '/devtools/messages', builder: (_, _) => const MessageSimulatorScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => _Shell(shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dayclose', builder: (_, _) => const DayCloseScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen())]),
        ],
      ),
    ],
  );
});

class _Shell extends ConsumerWidget {
  const _Shell(this.shell);
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      // Portal / tablet layout: persistent rail, content constrained for readability.
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            leading: Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Column(children: [const Icon(Icons.account_balance_wallet, size: 32), const SizedBox(height: 4), Text(s('app'), style: Theme.of(context).textTheme.labelLarge)])),
            destinations: [
              NavigationRailDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: Text(s('home'))),
              NavigationRailDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: Text(s('transactions'))),
              NavigationRailDestination(icon: const Icon(Icons.lock_clock_outlined), selectedIcon: const Icon(Icons.lock_clock), label: Text(s('dayclose'))),
              NavigationRailDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people), label: Text(s('customers'))),
              NavigationRailDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart), label: Text(s('reports'))),
              NavigationRailDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: Text(s('settings'))),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: shell))),
        ]),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard), label: s('home')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long), label: s('transactions')),
          NavigationDestination(icon: const Icon(Icons.lock_clock_outlined), selectedIcon: const Icon(Icons.lock_clock), label: s('dayclose')),
          NavigationDestination(icon: const Icon(Icons.people_outline), selectedIcon: const Icon(Icons.people), label: s('customers')),
          NavigationDestination(icon: const Icon(Icons.bar_chart_outlined), selectedIcon: const Icon(Icons.bar_chart), label: s('reports')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: s('settings')),
        ],
      ),
    );
  }
}
