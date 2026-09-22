import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../receipts/receipt.dart';

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
        if (value && !await AppLock.authenticate(s('lock_prompt'))) return;
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
          SwitchListTile(
            secondary: Icon(AppTheme.walletIcon(w.kind), color: AppTheme.walletColor(w.kind)),
            title: Text(w.nameIn(code)),
            subtitle: w.accountNumber == null ? null : Text(bnDigits(w.accountNumber!, code)),
            value: w.isActive,
            onChanged: w.kind == WalletKind.cash ? null : (v) => ref.read(repositoryProvider).setWalletActive(w.id, v),
          ),
        ListTile(leading: const Icon(Icons.add), title: Text(s('add_wallet')), onTap: () => _addWallet(context, ref)),
        _header(context, s('rates')),
        for (final r in rules)
          ListTile(
            dense: true,
            leading: Icon(AppTheme.walletIcon(r.walletKind), color: AppTheme.walletColor(r.walletKind)),
            title: Text('${code == 'bn' ? r.walletKind.labelBn : r.walletKind.label} • ${code == 'bn' ? r.txType.labelBn : r.txType.label}'),
            trailing: Text('${bnDigits(_quotedRate(r).toStringAsFixed(2), code)} ${_modeLabel(s, r.mode)}'),
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
        Center(child: Text('AgentKhata v0.1.0', style: Theme.of(context).textTheme.labelSmall)),
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
      await ref.read(repositoryProvider).upsertWallet(
            kind: kind,
            label: label.text.trim().isEmpty ? kind.label : label.text.trim(),
            accountNumber: number.text.trim().isEmpty ? null : number.text.trim(),
            openingBalance: Paisa.tryParse(opening.text) ?? Paisa.zero,
          );
    }
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, db.CommissionRuleRow r) async {
    final s = ref.s;
    final ctl = TextEditingController(text: _quotedRate(r).toStringAsFixed(2));
    var mode = r.mode;
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
          );
    }
  }
}

/// The name and number printed on every receipt and statement.
class ReceiptHeaderTile extends ConsumerWidget {
  const ReceiptHeaderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final h = ref.watch(receiptHeaderProvider).value;
    return ListTile(
      leading: const Icon(Icons.storefront_outlined),
      title: Text(h?.name ?? ''),
      subtitle: Text(h?.phone?.isNotEmpty == true ? h!.phone! : s('receipt_header_sub')),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () async {
        final name = TextEditingController(text: h?.name);
        final phone = TextEditingController(text: h?.phone);
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(s('receipt_header')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: s('shop_name'))),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s('phone'))),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(s('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(s('save'))),
            ],
          ),
        );
        if (ok != true) return;
        final p = await SharedPreferences.getInstance();
        await p.setString(shopNameKey, name.text.trim());
        await p.setString(shopPhoneKey, phone.text.trim());
        ref.invalidate(receiptHeaderProvider);
      },
    );
  }
}
