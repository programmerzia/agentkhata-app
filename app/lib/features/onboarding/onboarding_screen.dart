import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../../platform/message_channel.dart';

/// Three steps, under a minute: language → wallets + current balances →
/// notification access. Everything else has sensible defaults.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _S();
}

class _S extends ConsumerState<OnboardingScreen> {
  int step = 0;
  final selected = <WalletKind>{WalletKind.bkash, WalletKind.nagad};
  final balances = <WalletKind, TextEditingController>{for (final k in WalletKind.values) k: TextEditingController()};

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LinearProgressIndicator(value: (step + 1) / 3),
            const SizedBox(height: 24),
            Expanded(child: [_lang(s, code), _wallets(s, code), _perm(s)][step]),
            FilledButton(
              onPressed: () async {
                if (step < 2) {
                  setState(() => step++);
                  return;
                }
                await _finish();
              },
              child: Padding(padding: const EdgeInsets.all(10), child: Text(step == 2 ? s('finish') : s('continue'))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _lang(S s, String code) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.account_balance_wallet, size: 72, color: AppTheme.seed),
        const SizedBox(height: 16),
        Text(s('welcome'), style: Theme.of(context).textTheme.headlineMedium),
        Text(s('welcome_sub'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 32),
        Text(s('language'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: code,
          onChanged: (v) => ref.read(localeProvider.notifier).set(v!),
          child: const Column(children: [RadioListTile(value: 'bn', title: Text('বাংলা')), RadioListTile(value: 'en', title: Text('English'))]),
        ),
      ]);

  Widget _wallets(S s, String code) => ListView(children: [
        Text(s('pick_wallets'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (final k in [WalletKind.bkash, WalletKind.nagad, WalletKind.rocket, WalletKind.upay, WalletKind.tap, WalletKind.recharge, WalletKind.bank]) ...[
          CheckboxListTile(
            value: selected.contains(k),
            onChanged: (v) => setState(() => v! ? selected.add(k) : selected.remove(k)),
            secondary: Icon(AppTheme.walletIcon(k), color: AppTheme.walletColor(k)),
            title: Text(code == 'bn' ? k.labelBn : k.label),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (selected.contains(k))
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
              child: TextField(controller: balances[k], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('opening_balance'), prefixText: '৳ ')),
            ),
        ],
        const Divider(),
        ListTile(
          leading: Icon(AppTheme.walletIcon(WalletKind.cash), color: AppTheme.walletColor(WalletKind.cash)),
          title: Text(code == 'bn' ? WalletKind.cash.labelBn : WalletKind.cash.label),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
          child: TextField(controller: balances[WalletKind.cash], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: s('opening_balance'), prefixText: '৳ ')),
        ),
      ]);

  Widget _perm(S s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.bolt, size: 72, color: Colors.amber),
        const SizedBox(height: 16),
        Text(s('notif_access'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(s('notif_access_desc'), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(onPressed: () => MessageChannel.openNotificationAccessSettings().catchError((_) {}), icon: const Icon(Icons.settings), label: Text(s('enable'))),
      ]);

  Future<void> _finish() async {
    final repo = ref.read(repositoryProvider);
    final now = DateTime.now();
    final cashId = await repo.ensureCashWallet();
    await repo.upsertWallet(id: cashId, kind: WalletKind.cash, label: 'Cash', openingBalance: Paisa.tryParse(balances[WalletKind.cash]!.text) ?? Paisa.zero, openingAt: now);
    for (final k in selected) {
      await repo.upsertWallet(kind: k, label: k.label, openingBalance: Paisa.tryParse(balances[k]!.text) ?? Paisa.zero, openingAt: now);
    }
    await repo.seedDefaultRulesIfEmpty();
    await ref.read(onboardedProvider.notifier).done();
    if (mounted) context.go('/');
  }
}
