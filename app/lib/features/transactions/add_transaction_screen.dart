import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../voice/voice_amount.dart';

/// Manual entry. Auto capture covers operator traffic; this is for cash
/// expenses, drawings, recharge, baki, and corrections.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.presetType, this.customerId});
  final String? presetType;
  final String? customerId;
  @override
  ConsumerState<AddTransactionScreen> createState() => _S();
}

class _S extends ConsumerState<AddTransactionScreen> {
  final amount = TextEditingController();
  final note = TextEditingController();
  final phone = TextEditingController();
  TxType type = TxType.cashIn;
  String? walletId;
  String? counterWalletId;
  String? customerId;
  DateTime when = DateTime.now();

  static const manualTypes = [
    TxType.cashIn, TxType.cashOut, TxType.b2bIn, TxType.b2bOut, TxType.recharge, TxType.sendMoney,
    TxType.expense, TxType.drawing, TxType.capital, TxType.cashMove, TxType.bakiGiven, TxType.bakiReceived, TxType.adjustment,
  ];

  @override
  void initState() {
    super.initState();
    if (widget.presetType != null) type = TxType.values.firstWhere((t) => t.name == widget.presetType, orElse: () => TxType.cashIn);
    customerId = widget.customerId;
  }

  bool get needsCustomer => type == TxType.bakiGiven || type == TxType.bakiReceived;
  bool get needsCounterWallet => type == TxType.cashMove || type == TxType.b2bIn || type == TxType.b2bOut;
  bool get isCashOnly => const {TxType.expense, TxType.drawing, TxType.capital, TxType.bakiGiven, TxType.bakiReceived}.contains(type);

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = ref.watch(walletsProvider).value ?? [];
    final customers = ref.watch(customersProvider).value ?? [];
    final cashId = ref.watch(cashWalletIdProvider);
    final mfs = wallets.where((w) => w.kind != WalletKind.cash).toList();
    walletId ??= isCashOnly ? cashId : (mfs.isNotEmpty ? mfs.first.id : cashId);
    if (isCashOnly) walletId = cashId;
    counterWalletId ??= cashId;

    return Scaffold(
      appBar: AppBar(title: Text(s('add'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in manualTypes)
            ChoiceChip(label: Text(code == 'bn' ? t.labelBn : t.label), selected: type == t, onSelected: (_) => setState(() {
              type = t;
              if (isCashOnly) walletId = cashId;
            })),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Theme.of(context).textTheme.headlineMedium,
          decoration: InputDecoration(
            labelText: s('amount'),
            prefixText: '৳ ',
            /*
             * Dictation fills the field and stops there: the agent still reads
             * the number and still taps save. A mishearing that costs a glance
             * is a nuisance; one that posts money is a loss.
             */
            suffixIcon: VoiceAmountButton(
              tooltip: s('voice_amount'),
              onAmount: (value) => amount.text = value.value % 100 == 0
                  ? (value.value ~/ 100).toString()
                  : value.taka.toStringAsFixed(2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!isCashOnly)
          DropdownButtonFormField<String>(
            initialValue: walletId,
            decoration: InputDecoration(labelText: s('wallet')),
            items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text(code == 'bn' ? w.kind.labelBn : w.label))],
            onChanged: (v) => setState(() => walletId = v),
          ),
        if (needsCounterWallet) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: counterWalletId,
            decoration: InputDecoration(labelText: '${s('wallet')} 2'),
            items: [for (final w in wallets) DropdownMenuItem(value: w.id, child: Text(code == 'bn' ? w.kind.labelBn : w.label))],
            onChanged: (v) => setState(() => counterWalletId = v),
          ),
        ],
        if (needsCustomer) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: customerId,
            decoration: InputDecoration(labelText: s('customer')),
            items: [for (final c in customers) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => customerId = v),
          ),
        ],
        if (type == TxType.cashIn || type == TxType.cashOut || type == TxType.sendMoney || type == TxType.recharge) ...[
          const SizedBox(height: 12),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s('phone'))),
        ],
        const SizedBox(height: 12),
        TextField(controller: note, decoration: InputDecoration(labelText: s('note'))),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(bnDigits('${when.day}/${when.month}/${when.year}  ${TimeOfDay.fromDateTime(when).format(context)}', code)),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d == null || !context.mounted) return;
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(when));
            setState(() => when = DateTime(d.year, d.month, d.day, t?.hour ?? when.hour, t?.minute ?? when.minute));
          },
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: Padding(padding: const EdgeInsets.all(8), child: Text(s('save')))),
      ]),
    );
  }

  Future<void> _save() async {
    final amt = Paisa.tryParse(amount.text);
    if (amt == null || amt.value <= 0 || walletId == null) return;
    if (needsCustomer && customerId == null) return;
    final repo = ref.read(repositoryProvider);
    final wallets = ref.read(walletsProvider).value ?? [];
    final w = wallets.firstWhere((x) => x.id == walletId);
    final engine = CommissionEngine(await repo.commissionRules());
    final tx = Transaction(
      id: newId(),
      walletId: walletId!,
      type: type,
      amount: amt,
      commission: engine.commissionFor(kind: w.kind, type: type, amount: amt),
      counterparty: phone.text.isEmpty ? null : phone.text.trim(),
      occurredAt: when,
      source: TxSource.manual,
      note: note.text.isEmpty ? null : note.text.trim(),
      customerId: needsCustomer ? customerId : null,
      counterWalletId: needsCounterWallet ? counterWalletId : null,
    );
    await repo.insertTransaction(tx);
    if (mounted) context.pop();
  }
}
