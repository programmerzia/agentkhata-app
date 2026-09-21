import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../../platform/message_channel.dart';
import '../../sync/api_client.dart';
import '../../sync/enum_index.dart';
import '../../sync/sync_providers.dart';
import '../setup/capture_checklist.dart';
import '../setup/operator_apps.dart';

/// Setup, in under a minute, with nothing to learn.
///
/// ## Two ways in
///
/// Most agents start with one phone: they tick their operators, type the
/// balances they can see in the operator apps, and are done. A shop that runs
/// Upay on a second handset adds that phone differently — it signs in and
/// takes the shop's wallets as they are, because the books are already open
/// and a second set of opening balances would count the same money twice.
///
/// ## The answers are already filled in
///
/// Every operator whose app is on this phone is ticked before the agent looks.
/// The question on screen is not "which services do you offer?" but "is this
/// right?", which is answered with a tap.
///
/// ## Capture is part of setup, not a setting
///
/// The last step is the checklist that makes transactions arrive by
/// themselves — notification access, battery saver, the manufacturer's own
/// auto-start switch — each one tap to the right system screen, each turning
/// green on return. Left to a settings page, these are the switches that are
/// never found, and the product silently does nothing.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _S();
}

enum _Path { newShop, joinShop }

class _S extends ConsumerState<OnboardingScreen> {
  int step = 0;
  _Path path = _Path.newShop;

  // A new shop.
  final selected = <WalletKind>{};
  final balances = <WalletKind, TextEditingController>{for (final k in WalletKind.values) k: TextEditingController()};

  // Joining a shop.
  List<Map<String, dynamic>>? shopWallets;
  final joinCaptures = <String>{};
  Set<String>? _joinedWith;
  Set<WalletKind> installed = const {};
  bool joining = false;
  String? joinError;

  bool get _canJoin => ApiConfig.isConfigured;
  int get _steps => _canJoin ? 4 : 3;

  @override
  void initState() {
    super.initState();
    operatorsOnThisPhone().then((kinds) {
      if (!mounted) return;
      setState(() {
        installed = kinds;
        // A phone with none of the apps (an emulator, a new phone) starts
        // from the two most agents run.
        selected.addAll(kinds.isEmpty ? const {WalletKind.bkash, WalletKind.nagad} : kinds);
      });
    });
  }

  @override
  void dispose() {
    for (final c in balances.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);

    final pages = <Widget>[
      _welcome(s, code),
      if (_canJoin) _choosePath(s),
      if (path == _Path.newShop) _wallets(s, code) else _join(s, code),
      _capture(s),
    ];
    final last = step == pages.length - 1;
    final blocked = path == _Path.joinShop && pages[step] is _JoinMarker && shopWallets == null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Progress(step: step, total: _steps),
            const SizedBox(height: 20),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: KeyedSubtree(key: ValueKey(step), child: pages[step]))),
            const SizedBox(height: 12),
            Row(children: [
              if (step > 0)
                IconButton.outlined(
                  onPressed: () => setState(() => step--),
                  icon: const Icon(Icons.arrow_back),
                ),
              if (step > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: blocked ? null : () => last ? _finish() : _next(),
                  child: Text(last ? s('finish') : s('continue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _next() async {
    final pageIsJoin = path == _Path.joinShop && step == (_canJoin ? 2 : 1);
    // Join once per choice: going back and forward again must not re-join,
    // but changing which accounts this phone reads should.
    final choice = {...joinCaptures};
    final alreadyJoined = _joinedWith != null && _joinedWith!.length == choice.length && _joinedWith!.containsAll(choice);
    if (pageIsJoin && shopWallets != null && !alreadyJoined) {
      final svc = ref.read(syncServiceProvider);
      if (svc != null) {
        await svc.joinShop(wallets: shopWallets!, captures: choice);
        _joinedWith = choice;
      }
    }
    if (!mounted) return;
    setState(() => step++);
  }

  // ---- 1. welcome and language ----
  Widget _welcome(S s, String code) => ListView(children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.seed, AppTheme.navy]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 20),
            Text(s('welcome'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(s('welcome_sub'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: .85))),
          ]),
        ),
        const SizedBox(height: 28),
        Text(s('language'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'bn', label: Text('বাংলা')), ButtonSegment(value: 'en', label: Text('English'))],
          selected: {code},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity(vertical: 2)),
          onSelectionChanged: (v) => ref.read(localeProvider.notifier).set(v.first),
        ),
      ]);

  // ---- 2. which way in ----
  Widget _choosePath(S s) => ListView(children: [
        Text(s('setup_how'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        _PathCard(
          icon: Icons.storefront_outlined,
          title: s('setup_new_title'),
          subtitle: s('setup_new_sub'),
          selected: path == _Path.newShop,
          onTap: () => setState(() => path = _Path.newShop),
        ),
        const SizedBox(height: 12),
        _PathCard(
          icon: Icons.add_to_home_screen_outlined,
          title: s('setup_join_title'),
          subtitle: s('setup_join_sub'),
          selected: path == _Path.joinShop,
          onTap: () => setState(() => path = _Path.joinShop),
        ),
      ]);

  // ---- 3a. a new shop: wallets and balances ----
  Widget _wallets(S s, String code) => ListView(children: [
        Text(s('pick_wallets'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        for (final k in [WalletKind.bkash, WalletKind.nagad, WalletKind.rocket, WalletKind.upay, WalletKind.tap, WalletKind.recharge, WalletKind.bank])
          _WalletPick(
            kind: k,
            label: code == 'bn' ? k.labelBn : k.label,
            found: installed.contains(k) ? s('setup_found_app') : null,
            selected: selected.contains(k),
            onChanged: (v) => setState(() => v ? selected.add(k) : selected.remove(k)),
            balance: balances[k]!,
            balanceLabel: s('opening_balance'),
          ),
        const SizedBox(height: 8),
        _WalletPick(
          kind: WalletKind.cash,
          label: code == 'bn' ? WalletKind.cash.labelBn : WalletKind.cash.label,
          selected: true,
          onChanged: null,
          balance: balances[WalletKind.cash]!,
          balanceLabel: s('opening_balance'),
        ),
      ]);

  // ---- 3b. joining a shop ----
  Widget _join(S s, String code) => _JoinMarker(
        child: ListView(children: [
          Text(shopWallets == null ? s('setup_join_title') : s('setup_pick_captures'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(shopWallets == null ? s('setup_join_signin_sub') : s('setup_pick_captures_sub'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          if (shopWallets == null) ...[
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: joining ? null : _signInAndLoad,
              icon: joining ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
              label: Text(s('setup_join_signin')),
            ),
            if (joinError != null) ...[
              const SizedBox(height: 12),
              Text(joinError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ] else
            for (final w in shopWallets!.where((w) => !const {'cash', 'bank', 'recharge'}.contains(w['kind'])))
              () {
                final kind = WalletKindIndex.ofName(w['kind']);
                final id = w['id'] as String;
                final number = w['accountNumber'] as String?;
                return _WalletPick(
                  kind: kind,
                  label: '${code == 'bn' ? kind.labelBn : kind.label}${number == null ? '' : '  ·  $number'}',
                  found: installed.contains(kind) ? s('setup_found_app') : null,
                  selected: joinCaptures.contains(id),
                  onChanged: (v) => setState(() => v ? joinCaptures.add(id) : joinCaptures.remove(id)),
                );
              }(),
        ]),
      );

  Future<void> _signInAndLoad() async {
    setState(() {
      joining = true;
      joinError = null;
    });
    try {
      final identity = await MessageChannel.identity();
      final paired = await ref.read(deviceSessionProvider).pair(deviceName: identity?.model ?? 'Android phone');
      if (!paired) throw StateError('not paired');
      ref.invalidate(deviceTokenProvider);
      await ref.read(deviceTokenProvider.future);
      final svc = ref.read(syncServiceProvider);
      if (svc == null) throw StateError('no sync');
      final wallets = await svc.shopWallets();
      setState(() {
        shopWallets = wallets;
        joinCaptures
          ..clear()
          ..addAll(wallets.where((w) => installed.contains(WalletKindIndex.ofName(w['kind']))).map((w) => w['id'] as String));
      });
    } catch (_) {
      setState(() => joinError = ref.s('setup_join_failed'));
    } finally {
      if (mounted) setState(() => joining = false);
    }
  }

  // ---- 4. capture ----
  Widget _capture(S s) => ListView(children: [
        Text(s('setup_capture_title'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(s('setup_capture_sub'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        const CaptureChecklist(),
      ]);

  Future<void> _finish() async {
    if (path == _Path.newShop) {
      final repo = ref.read(repositoryProvider);
      final now = DateTime.now();
      final cashId = await repo.ensureCashWallet();
      await repo.upsertWallet(id: cashId, kind: WalletKind.cash, label: 'Cash', openingBalance: Paisa.tryParse(balances[WalletKind.cash]!.text) ?? Paisa.zero, openingAt: now);
      for (final k in selected) {
        await repo.upsertWallet(kind: k, label: k.label, openingBalance: Paisa.tryParse(balances[k]!.text) ?? Paisa.zero, openingAt: now);
      }
      await repo.seedDefaultRulesIfEmpty();
    }
    await ref.read(onboardedProvider.notifier).done();
    if (mounted) context.go('/');
  }
}

/// Marks the join page, so the continue button can wait for sign-in.
class _JoinMarker extends StatelessWidget {
  const _JoinMarker({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});
  final int step;
  final int total;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      for (var i = 0; i < total; i++)
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 5,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            decoration: BoxDecoration(color: i <= step ? scheme.primary : scheme.primary.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
          ),
        ),
    ]);
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: .5) : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: scheme.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? scheme.primary : scheme.outline),
          ]),
        ),
      ),
    );
  }
}

/// One operator: its colour, its name, whether its app was found here, and —
/// for a new shop — the balance the agent can read off that app right now.
class _WalletPick extends StatelessWidget {
  const _WalletPick({
    required this.kind,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.found,
    this.balance,
    this.balanceLabel,
  });

  final WalletKind kind;
  final String label;
  final String? found;
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final TextEditingController? balance;
  final String? balanceLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.walletColor(kind);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? color.withValues(alpha: .6) : scheme.outlineVariant, width: selected ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
        child: Column(children: [
          Row(children: [
            if (onChanged != null) Checkbox(value: selected, activeColor: color, onChanged: (v) => onChanged!(v ?? false)) else const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Icon(AppTheme.walletIcon(kind), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
            if (found != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
                child: Text(found!, style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
              ),
          ]),
          if (selected && balance != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: TextField(
                controller: balance,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: balanceLabel, prefixText: '৳ '),
              ),
            ),
        ]),
      ),
    );
  }
}
