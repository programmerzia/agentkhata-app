import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../data/database.dart' as db;
import '../../data/repository.dart';
import '../../l10n/strings.dart';
import 'tx_tile.dart';

/// Messages the parser could not confidently post, plus auto-posted
/// transactions flagged for review. One tap to accept or classify.
class UnsortedScreen extends ConsumerWidget {
  const UnsortedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final raws = ref.watch(unsortedProvider).value ?? [];
    final pending = (ref.watch(transactionsProvider).value ?? []).where((t) => t.status == TxStatus.pendingReview).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s('unsorted'))),
      body: ListView(children: [
        if (pending.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(s('pending'), style: Theme.of(context).textTheme.titleMedium)),
        for (final t in pending)
          Dismissible(
            key: ValueKey(t.id),
            background: Container(color: Colors.green, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 24), child: const Icon(Icons.check, color: Colors.white)),
            secondaryBackground: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), child: const Icon(Icons.delete, color: Colors.white)),
            onDismissed: (d) => ref.read(repositoryProvider).setStatus(t.id, d == DismissDirection.startToEnd ? TxStatus.posted : TxStatus.voided),
            child: TxTile(t: t),
          ),
        if (raws.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(s('unsorted'), style: Theme.of(context).textTheme.titleMedium)),
        for (final r in raws) _RawCard(r: r, code: code),
        if (raws.isEmpty && pending.isEmpty) const Padding(padding: EdgeInsets.all(48), child: Center(child: Icon(Icons.inbox, size: 64, color: Colors.grey))),
      ]),
    );
  }
}

class _RawCard extends ConsumerWidget {
  const _RawCard({required this.r, required this.code});
  final db.RawMessageRow r;
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final suspicious = r.parseStatus == ParseStatus.suspicious;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: suspicious ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (suspicious) ...[Icon(Icons.warning_amber, color: Theme.of(context).colorScheme.error, size: 18), const SizedBox(width: 6), Text(s('suspicious'), style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700))],
            const Spacer(),
            Text('${r.sender}  ${bnDigits(DateFormat('d MMM h:mm a', code == 'bn' ? 'bn' : 'en').format(r.receivedAt), code)}', style: Theme.of(context).textTheme.labelSmall),
          ]),
          const SizedBox(height: 6),
          Text(r.body),
          if (r.reason != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.reason!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey))),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => ref.read(repositoryProvider).markRaw(r.id, ParseStatus.ignored), child: Text(s('ignore'))),
            FilledButton.tonal(onPressed: () => _classify(context, ref), child: Text(s('review'))),
          ]),
        ]),
      ),
    );
  }

  Future<void> _classify(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    final parsed = const MessageParser().parse(r.body, sender: r.sender, packageName: r.packageName, receivedAt: r.receivedAt);
    final wallets = ref.read(walletsProvider).value ?? [];
    final amountCtl = TextEditingController(text: parsed.amount?.taka.toStringAsFixed(2) ?? '');
    var type = parsed.type ?? TxType.cashIn;
    var walletId = wallets.where((w) => w.kind == parsed.operator).firstOrNull?.id ?? wallets.firstOrNull?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s('review')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amountCtl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('amount'))),
            const SizedBox(height: 8),
            DropdownButtonFormField<TxType>(
              initialValue: type,
              items: [for (final t in TxType.values.where((t) => t.isAutoCapturable)) DropdownMenuItem(value: t, child: Text(code == 'bn' ? t.labelBn : t.label))],
              onChanged: (v) => setSt(() => type = v!),
              decoration: InputDecoration(labelText: s('type')),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: walletId,
              items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text(code == 'bn' ? w.kind.labelBn : w.label))],
              onChanged: (v) => setSt(() => walletId = v),
              decoration: InputDecoration(labelText: s('wallet')),
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('accept')))],
        ),
      ),
    );
    if (ok != true || walletId == null) return;
    final amt = Paisa.tryParse(amountCtl.text);
    if (amt == null) return;
    final repo = ref.read(repositoryProvider);
    final w = wallets.firstWhere((x) => x.id == walletId);
    final engine = CommissionEngine(await repo.commissionRules());
    final tx = Transaction(
      id: newId(),
      walletId: walletId!,
      type: type,
      amount: amt,
      fee: parsed.fee ?? Paisa.zero,
      commission: engine.commissionFor(kind: w.kind, type: type, amount: amt, statedByOperator: parsed.commission),
      counterparty: parsed.counterparty,
      trxId: parsed.trxId,
      balanceAfter: parsed.balanceAfter,
      occurredAt: parsed.occurredAt ?? r.receivedAt,
      source: r.source,
      rawMessageId: r.id,
    );
    await repo.insertTransaction(tx);
    await repo.markRaw(r.id, ParseStatus.parsed, txId: tx.id);
  }
}
