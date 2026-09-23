import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../receipts/receipt.dart';

class TxTile extends ConsumerWidget {
  const TxTile({super.key, required this.t, this.onTap});
  final Transaction t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider);
    final s = ref.s;
    final wallets = ref.watch(walletsProvider).value ?? [];
    final w = wallets.where((x) => x.id == t.walletId).firstOrNull;
    final color = w == null ? Colors.grey : AppTheme.walletColor(w.kind);
    final debit = t.type.debitsWallet;
    final pending = t.status == TxStatus.pendingReview;
    final time = DateFormat('d MMM, h:mm a', code == 'bn' ? 'bn' : 'en').format(t.occurredAt);
    final sub = [
      if (w != null) w.nameIn(code),
      if (t.counterparty != null) bnDigits(t.counterparty!, code),
      if (t.note != null && t.note!.isNotEmpty) t.note!,
      bnDigits(time, code),
    ].join(' • ');
    return ListTile(
      // Every list opens the same sheet unless it has its own use for a tap.
      onTap: onTap ?? () => showTxDetail(context, ref, t),
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(AppTheme.txIcon(t.type), color: color, size: 20)),
      title: Row(children: [
        Text(code == 'bn' ? t.type.labelBn : t.type.label),
        if (pending) ...[const SizedBox(width: 6), Chip(label: Text(s('pending')), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, labelStyle: const TextStyle(fontSize: 11))],
        if (t.source != TxSource.manual) ...[const SizedBox(width: 6), const Icon(Icons.bolt, size: 14, color: Colors.amber)],
      ]),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${debit ? '-' : '+'}${Fmt.money(context, code, t.amount.value)}', style: TextStyle(fontWeight: FontWeight.w700, color: debit ? Theme.of(context).colorScheme.error : Colors.green.shade700)),
        if (t.commission.value > 0) Text('+${Fmt.money(context, code, t.commission.value)} ${s('commission')}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.teal)),
      ]),
    );
  }
}

/// A row whose value the agent will read out or paste somewhere: the trx id
/// a customer disputes, a meter number going into the biller's own site, the
/// token that turns the lights back on.
Widget _copyRow(BuildContext context, String k, String v, String copied) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(color: Colors.grey))),
        Flexible(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          tooltip: copied,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: v));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copied), duration: const Duration(seconds: 2)));
          },
          icon: const Icon(Icons.copy_rounded),
        ),
      ]),
    );

Widget _row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(k, style: const TextStyle(color: Colors.grey))), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]),
    );

/// One entry, in full, with what can be done to it: a receipt to send, a
/// capture to accept, a mistake to void (and un-void).
void showTxDetail(BuildContext context, WidgetRef ref, Transaction t) {
  final s = ref.s;
  final code = ref.read(localeProvider);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(repositoryProvider);
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code == 'bn' ? t.type.labelBn : t.type.label, style: Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height: 8),
          _row(s('amount'), Fmt.moneyOf(code, t.amount.value)),
          if (t.commission.value != 0) _row(s('commission'), Fmt.moneyOf(code, t.commission.value)),
          if (t.fee.value != 0) _row(s('fees'), Fmt.moneyOf(code, t.fee.value)),
          if (t.counterparty != null) _copyRow(sheet, s('phone'), t.counterparty!, s('copied')),
          if (t.trxId != null) _copyRow(sheet, 'TrxID', t.trxId!, s('copied')),
          if (t.billerName != null) _row(s('biller'), t.billerName!),
          if (t.billerAccount != null) _copyRow(sheet, s('biller_account'), t.billerAccount!, s('copied')),
          if (t.billerToken != null) _copyRow(sheet, s('biller_token'), t.billerToken!, s('copied')),
          if (t.balanceAfter != null) _row(s('balance_after'), Fmt.moneyOf(code, t.balanceAfter!.value)),
          _row(s('time'), bnDigits(DateFormat('d MMM yyyy, h:mm a', code == 'bn' ? 'bn' : 'en').format(t.occurredAt), code)),
          if (t.note != null) _row(s('note'), t.note!),
          const SizedBox(height: 16),
          if (t.status != TxStatus.voided)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(sheet);
                showReceipt(context, ref, t);
              },
              icon: const Icon(Icons.receipt_long),
              label: Text(s('receipt')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            if (t.status == TxStatus.pendingReview)
              FilledButton.tonalIcon(
                onPressed: () async {
                  await repo.setStatus(t.id, TxStatus.posted);
                  if (sheet.mounted) Navigator.pop(sheet);
                },
                icon: const Icon(Icons.check),
                label: Text(s('accept')),
              ),
            const Spacer(),
            if (t.status != TxStatus.voided)
              TextButton.icon(
                onPressed: () async {
                  final before = t.status;
                  await repo.setStatus(t.id, TxStatus.voided);
                  if (sheet.mounted) Navigator.pop(sheet);
                  messenger.showSnackBar(SnackBar(
                    content: Text(s('voided_one')),
                    action: SnackBarAction(label: s('undo'), onPressed: () => repo.setStatus(t.id, before)),
                  ));
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(s('void')),
                style: TextButton.styleFrom(foregroundColor: Theme.of(sheet).colorScheme.error),
              ),
          ]),
        ]),
      ),
    ),
  );
}
