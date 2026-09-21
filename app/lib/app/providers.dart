import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/core.dart' as core;
import '../data/database.dart';
import '../data/ingestion_service.dart';
import '../data/repository.dart';
import '../capture/queue_processor.dart';
import '../platform/message_channel.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<Repository>((ref) => Repository(ref.watch(databaseProvider)));
final ingestionProvider = Provider<IngestionService>((ref) => IngestionService(ref.watch(repositoryProvider)));

final prefsProvider = FutureProvider<SharedPreferences>((_) => SharedPreferences.getInstance());

/// 'bn' or 'en'.
class LocaleNotifier extends Notifier<String> {
  @override
  String build() {
    final p = ref.watch(prefsProvider).value;
    return p?.getString('locale') ?? 'bn';
  }

  Future<void> set(String code) async {
    state = code;
    (await SharedPreferences.getInstance()).setString('locale', code);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

class OnboardedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).value?.getBool('onboarded') ?? false;
  Future<void> done() async {
    state = true;
    (await SharedPreferences.getInstance()).setBool('onboarded', true);
  }
}

final onboardedProvider = NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

final walletsProvider = StreamProvider<List<core.Wallet>>((ref) => ref.watch(repositoryProvider).watchWallets());
final allWalletsProvider = StreamProvider<List<core.Wallet>>((ref) => ref.watch(repositoryProvider).watchWallets(activeOnly: false));
final transactionsProvider = StreamProvider<List<core.Transaction>>((ref) => ref.watch(repositoryProvider).watchAllPosted());
final customersProvider = StreamProvider<List<core.Customer>>((ref) => ref.watch(repositoryProvider).watchCustomers());
final unsortedProvider = StreamProvider<List<RawMessageRow>>((ref) => ref.watch(repositoryProvider).watchUnsorted());
final dayClosesProvider = StreamProvider<List<core.DayClose>>((ref) => ref.watch(repositoryProvider).watchDayCloses());
final ruleRowsProvider = StreamProvider<List<CommissionRuleRow>>((ref) => ref.watch(repositoryProvider).watchCommissionRuleRows());

final cashWalletIdProvider = Provider<String?>((ref) {
  final ws = ref.watch(walletsProvider).value ?? [];
  for (final w in ws) {
    if (w.kind == core.WalletKind.cash) return w.id;
  }
  return null;
});

final ledgerProvider = Provider<core.Ledger?>((ref) {
  final cash = ref.watch(cashWalletIdProvider);
  return cash == null ? null : core.Ledger(cashWalletId: cash);
});

/// Live balance per wallet id.
final balancesProvider = Provider<Map<String, core.Paisa>>((ref) {
  final ledger = ref.watch(ledgerProvider);
  final ws = ref.watch(walletsProvider).value ?? [];
  final txs = ref.watch(transactionsProvider).value ?? [];
  if (ledger == null) return {};
  return ledger.balances(ws, txs.where((t) => t.status == core.TxStatus.posted));
});

final floatAdviceProvider = Provider<Map<String, core.FloatAdvice>>((ref) {
  final ws = ref.watch(walletsProvider).value ?? [];
  final txs = ref.watch(transactionsProvider).value ?? [];
  final bal = ref.watch(balancesProvider);
  const advisor = core.FloatAdvisor();
  final now = DateTime.now();
  return {
    for (final w in ws.where((w) => w.kind.isMfs))
      w.id: advisor.advise(wallet: w, balance: bal[w.id] ?? core.Paisa.zero, txs: txs, now: now),
  };
});

final todaySummaryProvider = Provider<core.PeriodSummary>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? [];
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  return const core.Reports().summarize(txs, from: d0, to: d0.add(const Duration(days: 1)));
});

final receivablesProvider = Provider<Map<String, core.Paisa>>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? [];
  return const core.Reports().receivables(txs);
});

/// Keeps the capture queue drained while the UI is up.
///
/// Every captured message is already on disk in the native queue; this only
/// decides WHEN the UI engine processes it — on start, and whenever the native
/// side wakes it. With the UI closed, the background engine runs the same
/// [processCaptureQueue] instead.
final messageListenerProvider = Provider<void>((ref) {
  final ingest = ref.watch(ingestionProvider);
  Future<void> run() async {
    try {
      await processCaptureQueue(ingest);
    } catch (_) {/* not on Android, or the channel is missing */}
  }

  unawaited(run());
  StreamSubscription<void>? sub;
  try {
    sub = MessageChannel.wakes().listen((_) => run(), onError: (_) {});
  } catch (_) {}
  ref.onDispose(() => sub?.cancel());
});

final notificationAccessProvider = FutureProvider<bool>((_) async {
  try {
    return await MessageChannel.isNotificationAccessGranted();
  } catch (_) {
    return false;
  }
});
