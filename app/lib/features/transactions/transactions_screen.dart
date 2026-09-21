import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import 'tx_tile.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialWalletId});

  /// Opened from a wallet card: that wallet's entries, not all of them.
  final String? initialWalletId;
  @override
  ConsumerState<TransactionsScreen> createState() => _S();
}

class _S extends ConsumerState<TransactionsScreen> {
  String? walletId;
  String q = '';

  @override
  void initState() {
    super.initState();
    walletId = widget.initialWalletId;
  }

  @override
  void didUpdateWidget(covariant TransactionsScreen old) {
    super.didUpdateWidget(old);
    // The branch is kept alive by the shell, so a second tap on another
    // wallet arrives as an update rather than a new screen.
    if (widget.initialWalletId != old.initialWalletId) setState(() => walletId = widget.initialWalletId);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = ref.watch(walletsProvider).value ?? [];
    final all = ref.watch(transactionsProvider).value ?? [];
    final txs = all.where((t) {
      if (walletId != null && t.walletId != walletId) return false;
      if (q.isEmpty) return true;
      final needle = q.toLowerCase();
      return (t.trxId ?? '').toLowerCase().contains(needle) || (t.counterparty ?? '').contains(needle) || (t.note ?? '').toLowerCase().contains(needle);
    }).toList();

    final groups = <String, List<Transaction>>{};
    for (final t in txs) {
      groups.putIfAbsent(bnDigits(DateFormat('EEEE, d MMMM', code == 'bn' ? 'bn' : 'en').format(t.occurredAt), code), () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(title: Text(s('transactions'))),
      floatingActionButton: FloatingActionButton(onPressed: () => context.push('/add'), child: const Icon(Icons.add)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s('search')), onChanged: (v) => setState(() => q = v)),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(s('all')), selected: walletId == null, onSelected: (_) => setState(() => walletId = null))),
            for (final w in wallets)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(w.nameIn(code)), selected: walletId == w.id, onSelected: (_) => setState(() => walletId = w.id))),
          ]),
        ),
        Expanded(
          child: txs.isEmpty
              ? Center(child: Text(s('no_tx')))
              : ListView(padding: const EdgeInsets.only(bottom: 88), children: [
                  for (final e in groups.entries) ...[
                    Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(bnDigits(e.key, code), style: Theme.of(context).textTheme.labelLarge)),
                    for (final t in e.value) TxTile(t: t, onTap: () => _detail(context, t)),
                  ],
                ]),
        ),
      ]),
    );
  }

  void _detail(BuildContext context, Transaction t) {
    final s = ref.s;
    final code = ref.read(localeProvider);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code == 'bn' ? t.type.labelBn : t.type.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _row(s('amount'), Fmt.money(context, code, t.amount.value)),
          if (t.commission.value != 0) _row(s('commission'), Fmt.money(context, code, t.commission.value)),
          if (t.fee.value != 0) _row(s('fees'), Fmt.money(context, code, t.fee.value)),
          if (t.counterparty != null) _row(s('phone'), bnDigits(t.counterparty!, code)),
          if (t.trxId != null) _row('TrxID', t.trxId!),
          if (t.balanceAfter != null) _row('Balance', Fmt.money(context, code, t.balanceAfter!.value)),
          _row('Time', bnDigits(DateFormat('d MMM yyyy, h:mm a', code == 'bn' ? 'bn' : 'en').format(t.occurredAt), code)),
          if (t.note != null) _row(s('note'), t.note!),
          const SizedBox(height: 12),
          Row(children: [
            if (t.status == TxStatus.pendingReview)
              FilledButton.icon(
                onPressed: () async {
                  await ref.read(repositoryProvider).setStatus(t.id, TxStatus.posted);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.check),
                label: Text(s('accept')),
              ),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                await ref.read(repositoryProvider).setStatus(t.id, TxStatus.voided);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(s('void')),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: Colors.grey))), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
