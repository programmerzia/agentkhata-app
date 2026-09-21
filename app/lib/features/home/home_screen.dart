import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../settings/topup_tile.dart';
import '../setup/capture_checklist.dart';
import '../../sync/sync_providers.dart';
import '../../sync/sync_service.dart';
import '../transactions/tx_tile.dart';

/// Questions this phone owes the shop: "which of your two bKash numbers is
/// on this phone?" Asked once, answered with a tap, then gone.
final pendingChoicesProvider = FutureProvider<List<PendingChoice>>((ref) async {
  ref.watch(syncStatusProvider);
  final svc = ref.watch(syncServiceProvider);
  return svc == null ? const [] : svc.pendingChoices();
});

/// The phone's float board.
///
/// The same order as the portal's, because it is the same agent asking the
/// same questions: how much money is in the shop and where, is capture
/// working, which wallet runs out first, what just happened. The hero is the
/// whole shop — every phone's wallets and the one drawer — since the books are
/// shared; this phone's own part is the operators it captures.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = ref.watch(walletsProvider).value ?? [];
    final bal = ref.watch(balancesProvider);
    final advice = ref.watch(floatAdviceProvider);
    final today = ref.watch(todaySummaryProvider);
    final unsorted = ref.watch(unsortedProvider).value ?? [];
    final txs = (ref.watch(transactionsProvider).value ?? []).take(8).toList();
    final pendingCount = (ref.watch(transactionsProvider).value ?? []).where((t) => t.status == TxStatus.pendingReview).length;
    final health = kIsWeb ? null : ref.watch(phoneHealthProvider).value;
    final choices = ref.watch(pendingChoicesProvider).value ?? const [];

    var eMoney = 0;
    var cash = 0;
    for (final w in wallets) {
      final b = bal[w.id]?.value ?? 0;
      if (w.kind.isMfs) eMoney += b;
      if (w.kind == WalletKind.cash) cash += b;
    }
    String m(num v) => Fmt.money(context, code, v);

    // Worst first: the wallet that runs out soonest is the one to see.
    final operators = wallets.where((w) => w.kind != WalletKind.cash).toList()
      ..sort((a, b) => _urgency(advice[a.id]).compareTo(_urgency(advice[b.id])));

    return Scaffold(
      appBar: AppBar(title: Text(s('app')), actions: [
        IconButton(onPressed: () => context.push('/unsorted'), icon: Badge(isLabelVisible: unsorted.isNotEmpty || pendingCount > 0, label: Text(bnDigits('${unsorted.length + pendingCount}', code)), child: const Icon(Icons.inbox_outlined))),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/add'), icon: const Icon(Icons.add), label: Text(s('add'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
        _Hero(total: eMoney + cash, eMoney: eMoney, cash: cash),
        if (health != null && !health.capturing) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            text: s('health_banner'),
            onTap: () => context.go('/settings'),
          ),
        ],
        for (final choice in choices) ...[
          const SizedBox(height: 12),
          _Banner(
            icon: Icons.help_outline,
            color: AppTheme.seed,
            text: '${s('choose_account_title')} (${code == 'bn' ? choice.kind.labelBn : choice.kind.label})',
            onTap: () => _chooseAccount(context, ref, choice),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Stat(icon: Icons.trending_up, label: s('today_commission'), value: m(today.commission.value), color: Colors.teal)),
          const SizedBox(width: 12),
          Expanded(child: _Stat(icon: Icons.receipt_long_outlined, label: s('today_tx'), value: bnDigits('${today.count}', code), color: AppTheme.seed)),
        ]),
        const SizedBox(height: 22),
        Text(s('wallets'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final w in operators) _WalletCard(w: w, balance: bal[w.id] ?? Paisa.zero, advice: advice[w.id]),
        const SizedBox(height: 22),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(s('transactions'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          TextButton(onPressed: () => context.go('/transactions'), child: Text(s('all'))),
        ]),
        if (txs.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s('no_tx'), style: TextStyle(color: Theme.of(context).hintColor)))),
        for (final t in txs) TxTile(t: t),
      ]),
    );
  }

  static int _urgency(FloatAdvice? a) => switch (a?.level) {
        FloatLevel.critical => 0,
        FloatLevel.low => 1,
        FloatLevel.watch => 2,
        _ => 3,
      };

  Future<void> _chooseAccount(BuildContext context, WidgetRef ref, PendingChoice choice) async {
    final s = ref.s;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(title: Text(s('choose_account_title'), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(s('choose_account_sub'))),
          for (final c in choice.candidates)
            ListTile(
              leading: Icon(AppTheme.walletIcon(choice.kind), color: AppTheme.walletColor(choice.kind)),
              title: Text(c.accountNumber ?? c.label),
              subtitle: Text(c.label),
              onTap: () => Navigator.pop(context, c.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null) return;
    await ref.read(syncServiceProvider)?.answerChoice(localId: choice.localId, serverWalletId: picked);
    ref.invalidate(pendingChoicesProvider);
  }
}

/// The shop's money, in one number, and where it sits.
class _Hero extends ConsumerWidget {
  const _Hero({required this.total, required this.eMoney, required this.cash});
  final int total;
  final int eMoney;
  final int cash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final sync = ref.watch(syncStatusProvider).value;
    String m(num v) => Fmt.money(context, code, v);
    final white = Colors.white;
    final split = total <= 0 ? .5 : (eMoney / total).clamp(0.02, 0.98);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.seed, AppTheme.navy]),
        boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: .25), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s('hero_total'), style: TextStyle(color: white.withValues(alpha: .8), fontSize: 13))),
          if (sync != null) _SyncChip(status: sync),
        ]),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(m(total), style: Theme.of(context).textTheme.displaySmall?.copyWith(color: white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Row(children: [
              Expanded(flex: (split * 1000).round(), child: Container(color: AppTheme.blueprint)),
              const SizedBox(width: 2),
              Expanded(flex: ((1 - split) * 1000).round(), child: Container(color: Colors.greenAccent.shade400)),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Legend(color: AppTheme.blueprint, label: s('total_float'), value: m(eMoney)),
          _Legend(color: Colors.greenAccent.shade400, label: s('cash_in_hand'), value: m(cash)),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12)),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

/// Whether the shop's books on this phone are current — and, offline, that
/// nothing is lost: everything is on the phone and goes up when signal returns.
class _SyncChip extends ConsumerWidget {
  const _SyncChip({required this.status});
  final SyncStatus status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final (IconData icon, String label) = switch (status.state) {
      'ok' => (Icons.cloud_done_outlined, fill(s('synced_ago'), {'when': agoText(status.at!, code)})),
      'syncing' => (Icons.cloud_sync_outlined, s('syncing_now')),
      'error' => (Icons.cloud_off_outlined, s('sync_offline')),
      'read_only' => (Icons.lock_outline, s('sync_due')),
      _ => (Icons.cloud_outlined, s('sync_offline')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text, required this.onTap});
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right, color: color),
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 10),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color))),
          ]),
        ),
      );
}

/// Asking the distributor for float, in one tap.
///
/// The number in the message is the advisor's own suggestion, so the agent is
/// not doing arithmetic on a wallet that is about to run dry. It opens WhatsApp
/// with the text prepared but unsent: the send is the agent's, because a float
/// request is a message to a business partner.
class _LiftButton extends ConsumerWidget {
  const _LiftButton({required this.wallet, required this.advice});
  final Wallet wallet;
  final FloatAdvice advice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final lift = advice.suggestedLift();
    if (lift.value <= 0) return const SizedBox.shrink();

    return IconButton(
      tooltip: s('topup_request'),
      icon: const Icon(Icons.local_shipping_outlined),
      onPressed: () async {
        final number = await TopUpNumberTile.number();
        if (!context.mounted) return;
        if (number == null || number.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(s('topup_number')),
              action: SnackBarAction(label: s('settings'), onPressed: () => context.go('/settings')),
            ),
          );
          return;
        }
        final message = s('topup_message')
            .replaceAll('{wallet}', code == 'bn' ? wallet.kind.labelBn : wallet.label)
            .replaceAll('{amount}', Fmt.money(context, code, lift.value));
        final digits = number.replaceAll(RegExp(r'\D'), '');
        final intl = digits.startsWith('880') ? digits : '880${digits.replaceFirst(RegExp(r'^0'), '')}';
        await launchUrl(
          Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(message)}'),
          mode: LaunchMode.externalApplication,
        );
      },
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.w, required this.balance, this.advice});
  final Wallet w;
  final Paisa balance;
  final FloatAdvice? advice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider);
    final s = ref.s;
    final color = AppTheme.walletColor(w.kind);
    final level = advice?.level ?? FloatLevel.ok;
    final hoursLeft = advice?.hoursLeft;
    final tone = switch (level) {
      FloatLevel.critical => Theme.of(context).colorScheme.error,
      FloatLevel.low => Colors.orange.shade700,
      _ => Colors.green.shade600,
    };
    // The business day, filled to how much of it this float covers.
    final share = hoursLeft == null ? 1.0 : (hoursLeft / 12).clamp(0.03, 1.0);
    final runway = hoursLeft == null
        ? s('steady')
        : level == FloatLevel.critical && hoursLeft == 0
            ? s('critical_float')
            : '${s('runway')} ~${bnDigits(hoursLeft.toStringAsFixed(1), code)} ${s('hours')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/transactions?wallet=${w.id}'),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                      child: Icon(AppTheme.walletIcon(w.kind), color: color, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(code == 'bn' ? w.kind.labelBn : w.label,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (level == FloatLevel.low || level == FloatLevel.critical)
                      if (advice != null && w.kind != WalletKind.cash) _LiftButton(wallet: w, advice: advice!),
                  ]),
                  const SizedBox(height: 8),
                  Text(Fmt.money(context, code, balance.value),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: balance.isNegative ? Theme.of(context).colorScheme.error : null,
                          )),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: share, minHeight: 6, color: tone, backgroundColor: tone.withValues(alpha: .12)),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: Text(runway, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: level == FloatLevel.ok ? null : tone))),
                    if (w.accountNumber != null)
                      Text(bnDigits(w.accountNumber!, code), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).hintColor)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
