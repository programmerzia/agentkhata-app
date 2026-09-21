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

/// The wallets this phone captures for; null before it joins a shop.
final capturesProvider = FutureProvider<Set<String>?>((ref) => ref.watch(repositoryProvider).captures());

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

/// The shop's trading day and low-float threshold.
///
/// From the shop's settings once this phone has synced (the portal is where
/// they are edited), twelve hours and six until then. One source, so the
/// runway on this phone, on the portal and on the bell all agree about what
/// "low" means.
final shopHoursProvider = Provider<({int businessHours, int lowFloatHours})>((ref) {
  final prefs = ref.watch(prefsProvider).value;
  ref.watch(transactionsProvider); // re-read after syncs, which arrive as table changes
  return (
    businessHours: prefs?.getInt(shopBusinessHoursKey) ?? 12,
    lowFloatHours: prefs?.getInt(shopLowFloatHoursKey) ?? 6,
  );
});

const shopBusinessHoursKey = 'agentkhata.business_hours';
const shopLowFloatHoursKey = 'agentkhata.low_float_hours';

/// Every entry that moves money: posted, not pending review, not voided.
///
/// ONE rule for every total on every screen. Pending entries are a message the
/// parser was unsure about; until a person accepts one it must not move a
/// balance, a commission, a runway or a debt — and it must not move one screen
/// and not another, which is how a phone came to show one commission on Home
/// and a different one on Reports for the same day.
final postedProvider = Provider<List<core.Transaction>>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? const <core.Transaction>[];
  return [for (final t in txs) if (t.status == core.TxStatus.posted) t];
});

/// Live balance per wallet id — over every wallet, active or not.
///
/// A wallet switched off in settings still holds its money until it is
/// emptied; dropping it from the totals made the shop look poorer the moment
/// someone tidied the wallet list.
final balancesProvider = Provider<Map<String, core.Paisa>>((ref) {
  final ledger = ref.watch(ledgerProvider);
  final ws = ref.watch(allWalletsProvider).value ?? [];
  if (ledger == null) return {};
  return ledger.balances(ws, ref.watch(postedProvider));
});

/// The shop's money in the same four buckets the portal uses.
final moneyBucketsProvider = Provider<({int eMoney, int cash, int other, int total})>((ref) {
  final ws = ref.watch(allWalletsProvider).value ?? [];
  final bal = ref.watch(balancesProvider);
  var eMoney = 0, cash = 0, other = 0;
  for (final w in ws) {
    final b = bal[w.id]?.value ?? 0;
    if (w.kind.isMfs) {
      eMoney += b;
    } else if (w.kind == core.WalletKind.cash) {
      cash += b;
    } else {
      other += b;
    }
  }
  return (eMoney: eMoney, cash: cash, other: other, total: eMoney + cash + other);
});

final floatAdviceProvider = Provider<Map<String, core.FloatAdvice>>((ref) {
  final ws = ref.watch(walletsProvider).value ?? [];
  final bal = ref.watch(balancesProvider);
  final hours = ref.watch(shopHoursProvider);
  final advisor = core.FloatAdvisor(businessHoursPerDay: hours.businessHours, lowFloatHours: hours.lowFloatHours);
  final posted = ref.watch(postedProvider);
  final now = DateTime.now();
  return {
    for (final w in ws.where((w) => w.kind.isMfs))
      w.id: advisor.advise(wallet: w, balance: bal[w.id] ?? core.Paisa.zero, txs: posted, now: now),
  };
});

final todaySummaryProvider = Provider<core.PeriodSummary>((ref) {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  return const core.Reports().summarize(ref.watch(postedProvider), from: d0, to: d0.add(const Duration(days: 1)));
});

/// Entries waiting for a person to accept or void them — shown as a count,
/// never added into money.
final pendingCountProvider = Provider<int>((ref) {
  final txs = ref.watch(transactionsProvider).value ?? const <core.Transaction>[];
  return txs.where((t) => t.status == core.TxStatus.pendingReview).length;
});

final receivablesProvider = Provider<Map<String, core.Paisa>>((ref) {
  return const core.Reports().receivables(ref.watch(postedProvider));
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
