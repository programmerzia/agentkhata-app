import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';

/// One-tap day close: the app proposes closing balances from the ledger, the
/// agent types what the operator app / drawer actually shows, and any
/// difference is booked as an adjustment so tomorrow starts clean.
class DayCloseScreen extends ConsumerStatefulWidget {
  const DayCloseScreen({super.key});
  @override
  ConsumerState<DayCloseScreen> createState() => _S();
}

class _S extends ConsumerState<DayCloseScreen> {
  final Map<String, TextEditingController> actual = {};
  final note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final allWallets = ref.watch(walletsProvider).value ?? [];
    final captures = ref.watch(capturesProvider).value;
    // Close only what this phone counts: its own captured accounts and the
    // drawer. Another handset closes its Upay; this one never guesses it.
    final wallets = [for (final w in allWallets) if (captures == null || captures.contains(w.id) || w.kind == WalletKind.cash) w];
    final bal = ref.watch(balancesProvider);
    final closes = ref.watch(dayClosesProvider).value ?? [];
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final closedToday = closes.where((c) => c.date == d0).toList();
    final closedIds = {for (final c in closedToday) c.walletId};
    final open = [for (final w in wallets) if (!closedIds.contains(w.id)) w];
    final summary = ref.watch(todaySummaryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${s('dayclose')} • ${bnDigits(DateFormat('d MMM', code == 'bn' ? 'bn' : 'en').format(today), code)}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(child: _kv(s('today_tx'), bnDigits('${summary.count}', code))),
              Expanded(child: _kv(s('commission'), Fmt.money(context, code, summary.commission.value))),
              Expanded(child: _kv(s('expenses'), Fmt.money(context, code, summary.expenses.value))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (closedToday.isNotEmpty) ...[
          Row(children: [const Icon(Icons.verified, color: Colors.green), const SizedBox(width: 8), Text(s('closed'), style: Theme.of(context).textTheme.titleMedium)]),
          const SizedBox(height: 8),
          for (final c in closedToday) _ClosedRow(c: c, wallets: allWallets),
          const Divider(height: 32),
        ],
        for (final w in open) _WalletRow(w: w, expected: bal[w.id] ?? Paisa.zero, ctl: actual.putIfAbsent(w.id, TextEditingController.new)),
        const SizedBox(height: 12),
        TextField(controller: note, decoration: InputDecoration(labelText: s('note'))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: open.isEmpty ? null : () => _close(open, bal, d0), icon: const Icon(Icons.lock), label: Padding(padding: const EdgeInsets.all(8), child: Text(s('close_day')))),
        const SizedBox(height: 24),
        if (closes.isNotEmpty) Text(s('history'), style: Theme.of(context).textTheme.titleMedium),
        for (final c in closes.where((c) => c.date != d0).take(30)) _ClosedRow(c: c, wallets: allWallets, showDate: true),
      ]),
    );
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)), Text(v, style: const TextStyle(fontWeight: FontWeight.w700))]);

  Future<void> _close(List<Wallet> wallets, Map<String, Paisa> bal, DateTime d0) async {
    final repo = ref.read(repositoryProvider);
    final now = DateTime.now();
    var closed = 0;
    for (final w in wallets) {
      // A blank box is "not counted", not "matched": recording it as matching
      // would hide a shortfall nobody looked for.
      final typed = Paisa.tryParse(actual[w.id]?.text ?? '');
      if (typed == null) continue;
      final expected = bal[w.id] ?? Paisa.zero;
      final key = '${d0.toIso8601String()}_${w.id}';
      await repo.saveDayClose(DayClose(id: key, date: d0, walletId: w.id, expected: expected, actual: typed, note: note.text.isEmpty ? null : note.text, closedAt: now));
      closed++;
      final diff = typed - expected;
      if (diff.value != 0) {
        await repo.insertTransaction(Transaction(
          // Derived from the close, so a retried tap cannot book it twice.
          id: const Uuid().v5(Namespace.url.value, 'agentkhata:dayclose-adjustment:$key'),
          walletId: w.id,
          type: TxType.adjustment,
          amount: diff,
          occurredAt: now,
          source: TxSource.manual,
          note: ref.s('dayclose_adjustment'),
        ));
      }
    }
    if (closed == 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.s('dayclose_count_first'))));
      return;
    }
    for (final c in actual.values) {
      c.clear();
    }
    note.clear();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.s('closed'))));
  }
}

class _WalletRow extends ConsumerWidget {
  const _WalletRow({required this.w, required this.expected, required this.ctl});
  final Wallet w;
  final Paisa expected;
  final TextEditingController ctl;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final color = AppTheme.walletColor(w.kind);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(AppTheme.walletIcon(w.kind), color: color),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.nameIn(code), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${s('expected')}: ${Fmt.money(context, code, expected.value)}', style: Theme.of(context).textTheme.labelSmall),
          ])),
          SizedBox(
            width: 130,
            child: ListenableBuilder(
              listenable: ctl,
              builder: (_, _) {
                final typed = Paisa.tryParse(ctl.text);
                final diff = typed == null ? null : typed - expected;
                return TextField(
                  controller: ctl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  decoration: InputDecoration(
                    labelText: s('actual'),
                    helperText: diff == null || diff.value == 0 ? null : '${diff.isNegative ? '' : '+'}${Fmt.money(context, code, diff.value)}',
                    helperStyle: TextStyle(color: diff != null && diff.isNegative ? Theme.of(context).colorScheme.error : Colors.green),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _ClosedRow extends ConsumerWidget {
  const _ClosedRow({required this.c, required this.wallets, this.showDate = false});
  final DayClose c;
  final List<Wallet> wallets;
  final bool showDate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider);
    final w = wallets.where((x) => x.id == c.walletId).firstOrNull;
    final d = c.difference;
    return ListTile(
      dense: true,
      leading: Icon(w == null ? Icons.help_outline : AppTheme.walletIcon(w.kind), color: w == null ? null : AppTheme.walletColor(w.kind)),
      title: Text('${showDate ? '${bnDigits(DateFormat('d MMM', code == 'bn' ? 'bn' : 'en').format(c.date), code)} • ' : ''}${w == null ? '?' : (w.nameIn(code))}'),
      subtitle: Text('${Fmt.money(context, code, c.expected.value)} → ${Fmt.money(context, code, c.actual.value)}'),
      trailing: Text(d.value == 0 ? '✓' : '${d.isNegative ? '' : '+'}${Fmt.money(context, code, d.value)}', style: TextStyle(fontWeight: FontWeight.w700, color: d.value == 0 ? Colors.green : (d.isNegative ? Theme.of(context).colorScheme.error : Colors.orange))),
    );
  }
}
