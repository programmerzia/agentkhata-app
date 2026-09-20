import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../settings/topup_tile.dart';
import '../transactions/tx_tile.dart';

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

    var eMoney = 0;
    var cash = 0;
    for (final w in wallets) {
      final b = bal[w.id]?.value ?? 0;
      if (w.kind.isMfs) eMoney += b;
      if (w.kind == WalletKind.cash) cash += b;
    }
    String m(num v) => Fmt.money(context, code, v);

    return Scaffold(
      appBar: AppBar(title: Text(s('app')), actions: [
        IconButton(onPressed: () => context.push('/unsorted'), icon: Badge(isLabelVisible: unsorted.isNotEmpty || pendingCount > 0, label: Text('${unsorted.length + pendingCount}'), child: const Icon(Icons.inbox_outlined))),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => context.push('/add'), icon: const Icon(Icons.add), label: Text(s('add'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Row(children: [
          Expanded(child: _Stat(label: s('total_float'), value: m(eMoney), color: AppTheme.seed)),
          const SizedBox(width: 12),
          Expanded(child: _Stat(label: s('cash_in_hand'), value: m(cash), color: AppTheme.walletColor(WalletKind.cash))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Stat(label: s('today_commission'), value: m(today.commission.value), color: Colors.teal)),
          const SizedBox(width: 12),
          Expanded(child: _Stat(label: s('today_tx'), value: bnDigits('${today.count}', code), color: Colors.indigo)),
        ]),
        const SizedBox(height: 20),
        Text(s('wallets'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final w in wallets.where((w) => w.kind != WalletKind.cash)) _WalletCard(w: w, balance: bal[w.id] ?? Paisa.zero, advice: advice[w.id]),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(s('transactions'), style: Theme.of(context).textTheme.titleMedium),
          TextButton(onPressed: () => context.go('/transactions'), child: Text(s('all'))),
        ]),
        if (txs.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s('no_tx'), style: TextStyle(color: Theme.of(context).hintColor)))),
        for (final t in txs) TxTile(t: t),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color))),
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
    final warn = level == FloatLevel.low || level == FloatLevel.critical;
    return Card(
      color: warn ? Theme.of(context).colorScheme.errorContainer : null,
      child: ListTile(
        onTap: () => context.go('/transactions?wallet=${w.id}'),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .15), child: Icon(AppTheme.walletIcon(w.kind), color: color)),
        title: Text(code == 'bn' ? w.kind.labelBn : w.label),
        subtitle: advice?.hoursLeft != null
            ? Text('${s('runway')} ~${bnDigits(advice!.hoursLeft!.toStringAsFixed(1), code)} ${s('hours')}${warn ? '  •  ${s('low_float')}' : ''}')
            : (w.accountNumber != null ? Text(bnDigits(w.accountNumber!, code)) : null),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(Fmt.money(context, code, balance.value), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: balance.isNegative ? Theme.of(context).colorScheme.error : null)),
          if (warn && advice != null && w.kind != WalletKind.cash) _LiftButton(wallet: w, advice: advice!),
        ]),
      ),
    );
  }
}
