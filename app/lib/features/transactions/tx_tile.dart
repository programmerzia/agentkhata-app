import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';

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
    final time = DateFormat('d MMM, h:mm a').format(t.occurredAt);
    final sub = [
      if (w != null) (code == 'bn' ? w.kind.labelBn : w.kind.label),
      if (t.counterparty != null) bnDigits(t.counterparty!, code),
      if (t.note != null && t.note!.isNotEmpty) t.note!,
      bnDigits(time, code),
    ].join(' • ');
    return ListTile(
      onTap: onTap,
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
