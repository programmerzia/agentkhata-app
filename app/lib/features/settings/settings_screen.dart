import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../receipts/receipt.dart';
import '../update/update_check.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../data/database.dart' as db;
import '../../l10n/strings.dart';
import 'sync_tile.dart';
import '../lock/app_lock.dart';
import 'topup_tile.dart';
import 'captures_editor.dart';
import '../setup/capture_checklist.dart';

/// Turning the shutter on, when the phone can actually do it.
///
/// A switch that is present but always refuses is worse than one that is
/// absent, so a device with no fingerprint and no screen lock is told why
/// rather than offered a control that cannot work.
class _LockTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final available = ref.watch(lockAvailableProvider).value ?? false;
    final enabled = ref.watch(lockEnabledProvider).value ?? false;

    if (!available) {
      return ListTile(
        leading: const Icon(Icons.lock_outline),
        title: Text(s('lock_title')),
        subtitle: Text(s('lock_unavailable')),
      );
    }

    return SwitchListTile(
      secondary: Icon(enabled ? Icons.lock : Icons.lock_open),
      title: Text(s('lock_title')),
      subtitle: Text(s('lock_desc')),
      isThreeLine: true,
      value: enabled,
      onChanged: (value) async {
        /* Prove it works BEFORE turning it on. A lock enabled on a phone whose
           reader is broken is an agent locked out of their own books. */
        if (value && !await AppLock.authenticate(s('lock_prompt'))) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('lock_failed'))));
          return;
        }
        await AppLock.setEnabled(value);
        ref.invalidate(lockEnabledProvider);
      },
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = ref.watch(allWalletsProvider).value ?? [];
    final rules = ref.watch(ruleRowsProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(s('settings'))),
      body: ListView(children: [
        _header(context, s('cloud_sync')),
        const SyncTile(),
        if (!kIsWeb) ...[
          _header(context, s('health_title')),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: CaptureChecklist(dense: true),
          ),
          _header(context, s('captures_title')),
          const CapturesEditor(),
        ],
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(s('help')),
          subtitle: Text(s('help_desc')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/help'),
        ),
        /*
         * Debug builds only. It writes real entries through the real pipeline,
         * which is exactly what a tester wants and exactly what an agent must
         * never be able to tap by accident.
         */
        if (kDebugMode)
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Message simulator'),
            subtitle: const Text('Feed operator messages in without an operator account'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/devtools/messages'),
          ),
        _header(context, s('lock_title')),
        _LockTile(),
        _header(context, s('receipt')),
        const ReceiptHeaderTile(),
        _header(context, s('topup_request')),
        const TopUpNumberTile(),
        const WidgetPinTile(),
        _header(context, s('wallets')),
        for (final w in wallets)
          ListTile(
            leading: Icon(AppTheme.walletIcon(w.kind), color: AppTheme.walletColor(w.kind)),
            title: Text(w.nameIn(code)),
            // An operator account with no number cannot be matched to the
            // same account on another phone, so say so instead of leaving the
            // line blank. The cash drawer has no number to give.
            subtitle: w.accountNumber?.isNotEmpty == true
                ? Text(bnDigits(w.accountNumber!, code))
                : w.kind == WalletKind.cash
                    ? null
                    : Text(s('no_account_number'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: w.isActive,
                onChanged: w.kind == WalletKind.cash ? null : (v) => ref.read(repositoryProvider).setWalletActive(w.id, v),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_outlined, size: 20),
            ]),
            onTap: () => _editWallet(context, ref, w),
          ),
        ListTile(leading: const Icon(Icons.add), title: Text(s('add_wallet')), onTap: () => _addWallet(context, ref)),
        _header(context, s('service_charges')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(s('service_charges_sub'), style: Theme.of(context).textTheme.bodySmall),
        ),
        for (final r in rules.where((x) => x.txType == TxType.billPay))
          ListTile(
            dense: true,
            leading: Icon(AppTheme.walletIcon(r.walletKind), color: AppTheme.walletColor(r.walletKind)),
            title: Text('${code == 'bn' ? r.walletKind.labelBn : r.walletKind.label}${r.billerMatch?.isNotEmpty == true ? ' • ${r.billerMatch}' : ''}'),
            subtitle: Text(r.takenInCash ? s('in_cash_short') : s('in_wallet_short')),
            trailing: Text(
              '৳${bnDigits(_quotedRate(r).toStringAsFixed(2), code)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            onTap: () => _editRule(context, ref, r),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: Text(s('add_biller_rate')),
          subtitle: Text(s('add_biller_rate_sub')),
          onTap: () => _addBillerRate(context, ref),
        ),
        _header(context, s('rates')),
        for (final r in rules)
          ListTile(
            dense: true,
            leading: Icon(AppTheme.walletIcon(r.walletKind), color: AppTheme.walletColor(r.walletKind)),
            title: Text(
              '${code == 'bn' ? r.walletKind.labelBn : r.walletKind.label} • ${code == 'bn' ? r.txType.labelBn : r.txType.label}'
              '${r.billerMatch?.isNotEmpty == true ? ' • ${r.billerMatch}' : ''}',
            ),
            trailing: Text(
              '${bnDigits(_quotedRate(r).toStringAsFixed(2), code)} ${_modeLabel(s, r.mode)}${r.takenInCash ? ' · ${s('in_cash_short')}' : ''}',
            ),
            onTap: () => _editRule(context, ref, r),
          ),
        _header(context, s('language')),
        RadioGroup<String>(
          groupValue: code,
          onChanged: (v) => ref.read(localeProvider.notifier).set(v!),
          child: const Column(children: [
            RadioListTile(value: 'bn', title: Text('বাংলা')),
            RadioListTile(value: 'en', title: Text('English')),
          ]),
        ),
        _header(context, s('backup')),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: Text(s('export')),
          onTap: () async {
            final json = await ref.read(repositoryProvider).exportJson();
            final bytes = utf8.encode(jsonEncode(json));
            final name = 'agentkhata-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json';
            await shareBytes(bytes, name, 'application/json', 'AgentKhata backup');
          },
        ),
        const SizedBox(height: 32),
        const AboutVersionTile(),
        const SizedBox(height: 16),
      ]),
    );
  }

  /// The number the agent was quoted, from the stored parts-per-million ratio.
  /// Rates are shown in the unit their distributor uses, never in ppm.
  double _quotedRate(db.CommissionRuleRow r) => switch (r.mode) {
        RateMode.perThousand => r.ratePpm / 1000,
        RateMode.percent => r.ratePpm / 10000,
        RateMode.flat => (r.flatPoisha ?? 0) / 100,
        RateMode.slab => 0,
      };

  String _modeLabel(S s, RateMode m) => switch (m) { RateMode.perThousand => s('per_thousand'), RateMode.percent => s('percent'), RateMode.flat => s('flat'), RateMode.slab => 'slab' };

  Widget _header(BuildContext c, String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: Theme.of(c).textTheme.titleSmall?.copyWith(color: Theme.of(c).colorScheme.primary)));

  Future<void> _editWallet(BuildContext context, WidgetRef ref, Wallet w) async {
    final s = ref.s;
    final label = TextEditingController(text: w.label);
    final number = TextEditingController(text: w.accountNumber ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s('edit_wallet')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: label, decoration: InputDecoration(labelText: s('name'))),
          const SizedBox(height: 8),
          if (w.kind != WalletKind.cash)
            TextField(
            controller: number,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: s('account_number'), helperText: s('account_number_why'), helperMaxLines: 3),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s('save'))),
        ],
      ),
    );
    if (ok != true) return;
    final name = label.text.trim();
    await ref.read(repositoryProvider).editWallet(
          w.id,
          label: name.isEmpty ? w.label : name,
          accountNumber: number.text.trim().isEmpty ? null : number.text.trim(),
        );
  }

  Future<void> _addWallet(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    final code = ref.read(localeProvider);
    var kind = WalletKind.bkash;
    final label = TextEditingController();
    final number = TextEditingController();
    final opening = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s('add_wallet')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<WalletKind>(
              initialValue: kind,
              items: [for (final k in WalletKind.values.where((k) => k != WalletKind.cash)) DropdownMenuItem(value: k, child: Text(code == 'bn' ? k.labelBn : k.label))],
              onChanged: (v) => setSt(() => kind = v!),
            ),
            const SizedBox(height: 8),
            TextField(controller: label, decoration: InputDecoration(labelText: s('name'))),
            const SizedBox(height: 8),
            TextField(controller: number, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s('phone'))),
            const SizedBox(height: 8),
            TextField(controller: opening, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('opening_balance'))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('save')))],
        ),
      ),
    );
    if (ok == true) {
      final repo = ref.read(repositoryProvider);
      final id = await repo.upsertWallet(
        kind: kind,
        label: label.text.trim().isEmpty ? kind.label : label.text.trim(),
        accountNumber: number.text.trim().isEmpty ? null : number.text.trim(),
        openingBalance: Paisa.tryParse(opening.text) ?? Paisa.zero,
      );
      /*
       * The phone that adds an account reads it from the start.
       *
       * Once a phone joins a shop it records only the accounts on its own
       * capture list, and a list made when it joined cannot know about an
       * account added later. Every message for that account was ignored as
       * "another phone's", with nothing on screen to say why.
       */
      final captures = await repo.captures();
      if (captures != null && kind.isMfs) await repo.setCaptures({...captures, id});
    }
  }

  /// A rate for one biller, when a shop charges differently for, say, a WASA
  /// bill than an electricity one.
  Future<void> _addBillerRate(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    var kind = WalletKind.bkash;
    final biller = TextEditingController();
    final amount = TextEditingController(text: '5.00');
    var inCash = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(s('add_biller_rate')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<WalletKind>(
              initialValue: kind,
              decoration: InputDecoration(labelText: s('wallets')),
              items: [for (final k in WalletKind.values.where((k) => k.isMfs)) DropdownMenuItem(value: k, child: Text(k.label))],
              onChanged: (v) => setSt(() => kind = v ?? kind),
            ),
            const SizedBox(height: 8),
            TextField(controller: biller, decoration: InputDecoration(labelText: s('biller_rule'), hintText: 'NESCO')),
            const SizedBox(height: 8),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: s('flat'), prefixText: '৳ '),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: inCash,
              onChanged: (v) => setSt(() => inCash = v),
              title: Text(s('taken_in_cash')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('save'))),
          ],
        ),
      ),
    );
    if (ok != true || biller.text.trim().isEmpty) return;
    await ref.read(repositoryProvider).upsertRule(
          kind: kind,
          type: TxType.billPay,
          mode: RateMode.flat,
          ratePpm: 0,
          flatPoisha: ((double.tryParse(amount.text) ?? 0) * 100).round(),
          takenInCash: inCash,
          billerMatch: biller.text.trim(),
        );
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, db.CommissionRuleRow r) async {
    final s = ref.s;
    final ctl = TextEditingController(text: _quotedRate(r).toStringAsFixed(2));
    var mode = r.mode;
    var inCash = r.takenInCash;
    final biller = TextEditingController(text: r.billerMatch ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('${r.walletKind.label} • ${r.txType.label}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<RateMode>(
              segments: [ButtonSegment(value: RateMode.perThousand, label: Text(s('per_thousand'))), ButtonSegment(value: RateMode.percent, label: Text(s('percent'))), ButtonSegment(value: RateMode.flat, label: Text(s('flat')))],
              selected: {mode},
              onSelectionChanged: (v) => setSt(() => mode = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: true),
            if (r.txType == TxType.billPay) ...[
              const SizedBox(height: 8),
              TextField(
                controller: biller,
                decoration: InputDecoration(labelText: s('biller_rule'), helperText: s('biller_rule_help'), helperMaxLines: 2),
              ),
            ],
            const SizedBox(height: 8),
            /*
             * Where the money lands. An operator credits the wallet it was
             * earned in; a bill-pay service charge comes out of the
             * customer's hand as cash. Getting this wrong leaves the drawer
             * short and the wallet over at counting time, every single bill.
             */
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: inCash,
              onChanged: (v) => setSt(() => inCash = v),
              title: Text(s('taken_in_cash')),
              subtitle: Text(s('taken_in_cash_sub')),
              isThreeLine: true,
            ),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('save')))],
        ),
      ),
    );
    if (ok == true) {
      final quoted = double.tryParse(ctl.text) ?? _quotedRate(r);
      await ref.read(repositoryProvider).upsertRule(
            id: r.id,
            kind: r.walletKind,
            type: r.txType,
            mode: mode,
            ratePpm: CommissionRule.ppmFrom(mode, quoted),
            flatPoisha: mode == RateMode.flat ? (quoted * 100).round() : null,
            takenInCash: inCash,
            billerMatch: biller.text.trim().isEmpty ? null : biller.text.trim(),
          );
    }
  }
}

/// The shop details printed on every receipt and statement.
class ReceiptHeaderTile extends ConsumerWidget {
  const ReceiptHeaderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final h = ref.watch(receiptHeaderProvider).value;
    final details = [h?.owner, h?.address, h?.phone].whereType<String>().join(' • ');
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: Text(h?.name ?? ''),
      subtitle: Text(details.isEmpty ? s('receipt_header_sub') : details),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceiptHeaderScreen())),
    );
  }
}

class ReceiptHeaderScreen extends ConsumerStatefulWidget {
  const ReceiptHeaderScreen({super.key});

  @override
  ConsumerState<ReceiptHeaderScreen> createState() => _ReceiptHeaderScreenState();
}

class _ReceiptHeaderScreenState extends ConsumerState<ReceiptHeaderScreen> {
  final fields = <String, TextEditingController>{
    shopNameKey: TextEditingController(),
    shopOwnerKey: TextEditingController(),
    shopAddressKey: TextEditingController(),
    shopPhoneKey: TextEditingController(),
    shopFooterKey: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        for (final e in fields.entries) {
          e.value.text = p.getString(e.key) ?? '';
        }
      });
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    for (final e in fields.entries) {
      await p.setString(e.key, e.value.text.trim());
    }
    ref.invalidate(receiptHeaderProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    Widget field(String key, String label, {String? hint, TextInputType? type, int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            controller: fields[key],
            keyboardType: type,
            maxLines: lines,
            decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s('receipt_header'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(s('receipt_header_sub'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        field(shopNameKey, s('shop_name'), hint: s('shop_name_hint')),
        field(shopOwnerKey, s('shop_owner')),
        field(shopAddressKey, s('shop_address'), hint: s('shop_address_hint'), lines: 2),
        field(shopPhoneKey, s('phone'), type: TextInputType.phone),
        field(shopFooterKey, s('receipt_footer'), hint: s('receipt_thanks')),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: Text(s('save'))),
      ]),
    );
  }
}
