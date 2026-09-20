import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _S();
}

class _S extends ConsumerState<ReportsScreen> {
  int period = 1; // 0 today, 1 this month, 2 last month

  (DateTime, DateTime) get range {
    final n = DateTime.now();
    return switch (period) {
      0 => (DateTime(n.year, n.month, n.day), DateTime(n.year, n.month, n.day + 1)),
      1 => (DateTime(n.year, n.month), DateTime(n.year, n.month + 1)),
      _ => (DateTime(n.year, n.month - 1), DateTime(n.year, n.month)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final txs = ref.watch(transactionsProvider).value ?? [];
    final wallets = ref.watch(walletsProvider).value ?? [];
    final (from, to) = range;
    final r = const Reports().summarize(txs.where((t) => t.status == TxStatus.posted), from: from, to: to);
    String m(num v) => Fmt.money(context, code, v);
    final maxByType = r.byType.values.fold<int>(1, (a, b) => b.value > a ? b.value : a);

    return Scaffold(
      appBar: AppBar(title: Text(s('reports'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<int>(
          segments: [ButtonSegment(value: 0, label: Text(s('today'))), ButtonSegment(value: 1, label: Text(s('this_month'))), ButtonSegment(value: 2, label: Text(s('last_month')))],
          selected: {period},
          onSelectionChanged: (v) => setState(() => period = v.first),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _line(s('commission'), m(r.commission.value), Colors.teal),
              _line(s('fees'), '-${m(r.fees.value)}', Colors.orange),
              _line(s('expenses'), '-${m(r.expenses.value)}', Colors.red),
              const Divider(),
              _line(s('net_profit'), m(r.netProfit.value), r.netProfit.isNegative ? Colors.red : Colors.green, bold: true),
              const SizedBox(height: 4),
              _line(s('drawings'), m(r.drawings.value), Colors.grey),
              _line(s('count'), bnDigits('${r.count}', code), Colors.grey),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text(s('by_wallet'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final w in wallets.where((w) => (r.byWallet[w.id]?.value ?? 0) > 0))
          ListTile(dense: true, leading: Icon(AppTheme.walletIcon(w.kind), color: AppTheme.walletColor(w.kind)), title: Text(code == 'bn' ? w.kind.labelBn : w.label), trailing: Text(m(r.byWallet[w.id]!.value), style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(height: 16),
        Text(s('by_type'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final e in (r.byType.entries.toList()..sort((a, b) => b.value.value.compareTo(a.value.value))))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(AppTheme.txIcon(e.key), size: 16), const SizedBox(width: 6), Text(code == 'bn' ? e.key.labelBn : e.key.label), const Spacer(), Text(m(e.value.value), style: const TextStyle(fontWeight: FontWeight.w600))]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: e.value.value / maxByType, minHeight: 6)),
            ]),
          ),
      ]),
    );
  }

  Widget _line(String k, String v, Color c, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null))), Text(v, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: bold ? 18 : 14))]),
      );
}
