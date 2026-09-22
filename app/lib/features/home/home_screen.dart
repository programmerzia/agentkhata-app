import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../update/update_check.dart';
import '../../sync/sync_providers.dart';
import '../../sync/sync_service.dart';
import '../settings/topup_tile.dart';
import '../setup/capture_checklist.dart';
import '../transactions/tx_tile.dart';

/// Questions this phone owes the shop: "which of your two bKash numbers is
/// on this phone?" Asked once, answered with a tap, then gone.
final pendingChoicesProvider = FutureProvider<List<PendingChoice>>((ref) async {
  ref.watch(syncStatusProvider);
  final svc = ref.watch(syncServiceProvider);
  return svc == null ? const [] : svc.pendingChoices();
});

/// The phone's home: everything an agent checks during the day, one glance
/// each, and every common job one tap away.
///
/// ## The order
///
/// 1. Who and when — a greeting and the date, with the sync state.
/// 2. The shop's money, split where it sits, with today's three numbers.
/// 3. Anything broken — capture off, a question from the shop.
/// 4. Shortcuts: the eight things an agent does all day, one tap each.
/// 5. Wallets, as a strip of cards in the operators' own colours, worst first.
/// 6. How the week is going, who owes money, whether the day is closed.
/// 7. What just happened.
///
/// ## One set of numbers
///
/// Every figure here comes from the same providers every other screen uses —
/// posted entries only, the shop's own hours — so Home, Reports, Day close and
/// the home-screen widget cannot disagree about the same money.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = ref.watch(walletsProvider).value ?? [];
    final bal = ref.watch(balancesProvider);
    final advice = ref.watch(floatAdviceProvider);
    final unsorted = ref.watch(unsortedProvider).value ?? [];
    final pending = ref.watch(pendingCountProvider);
    final txs = (ref.watch(transactionsProvider).value ?? []).take(8).toList();
    final health = kIsWeb ? null : ref.watch(phoneHealthProvider).value;
    final choices = ref.watch(pendingChoicesProvider).value ?? const [];

    // Worst first: the wallet that runs out soonest is the one to see.
    final strip = wallets.where((w) => w.kind != WalletKind.cash).toList()
      ..sort((a, b) => _urgency(advice[a.id]).compareTo(_urgency(advice[b.id])));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add),
        label: Text(s('add')),
      ),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _Header(inboxCount: unsorted.length + pending)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            sliver: SliverList.list(children: [
              const UpdateBanner(),
              const _Hero(),
              if (health != null && !health.capturing) ...[
                const SizedBox(height: 12),
                _Banner(icon: Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, text: s('health_banner'), onTap: () => context.go('/settings')),
              ],
              for (final choice in choices) ...[
                const SizedBox(height: 12),
                _Banner(
                  icon: Icons.help_outline,
                  color: AppTheme.seed,
                  text: '${s('choose_account_title')} (${code == 'bn' ? choice.kind.labelBn : choice.kind.label})',
                  onTap: () => _chooseAccount(context, ref, choice),
                ),
              ],
              const SizedBox(height: 20),
              _SectionTitle(s('qa_title')),
              const _QuickActions(),
              if (strip.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionTitle(s('wallets'), action: s('all'), onAction: () => context.go('/settings')),
                SizedBox(
                  height: 168,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: strip.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _WalletCard(w: strip[i], balance: bal[strip[i].id] ?? Paisa.zero, advice: advice[strip[i].id]),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const _TrendCard(),
              const SizedBox(height: 12),
              const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _BakiCard()),
                SizedBox(width: 12),
                Expanded(child: _DayCloseCard()),
              ]),
              const SizedBox(height: 20),
              _SectionTitle(s('transactions'), action: s('all'), onAction: () => context.go('/transactions')),
              if (txs.isEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(s('no_tx'), style: TextStyle(color: Theme.of(context).hintColor))))
              else
                Card(child: Column(children: [for (final t in txs) TxTile(t: t)])),
            ]),
          ),
        ]),
      ),
    );
  }

  static int _urgency(FloatAdvice? a) => switch (a?.level) {
        FloatLevel.critical => 0,
        FloatLevel.low => 1,
        FloatLevel.watch => 2,
        _ => 3,
      };

  Future<void> _chooseAccount(BuildContext context, WidgetRef ref, PendingChoice choice) async {
    final s = ref.s;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(title: Text(s('choose_account_title'), style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(s('choose_account_sub'))),
          for (final c in choice.candidates)
            ListTile(
              leading: Icon(AppTheme.walletIcon(choice.kind), color: AppTheme.walletColor(choice.kind)),
              title: Text(c.accountNumber ?? c.label),
              subtitle: Text(c.label),
              onTap: () => Navigator.pop(context, c.id),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null) return;
    await ref.read(syncServiceProvider)?.answerChoice(localId: choice.localId, serverWalletId: picked);
    ref.invalidate(pendingChoicesProvider);
  }
}

// ---------------------------------------------------------------- header

class _Header extends ConsumerWidget {
  const _Header({required this.inboxCount});
  final int inboxCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final now = DateTime.now();
    final greeting = switch (now.hour) {
      >= 5 && < 12 => s('greet_morning'),
      >= 12 && < 16 => s('greet_noon'),
      >= 16 && < 19 => s('greet_afternoon'),
      >= 19 && < 23 => s('greet_evening'),
      _ => s('greet_night'),
    };
    final date = bnDigits(DateFormat('EEEE, d MMMM', code == 'bn' ? 'bn' : 'en').format(now), code);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(date, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        IconButton.filledTonal(
          onPressed: () => context.push('/unsorted'),
          icon: Badge(isLabelVisible: inboxCount > 0, label: Text(bnDigits('$inboxCount', code)), child: const Icon(Icons.inbox_outlined)),
        ),
        const SizedBox(width: 4),
        IconButton.filledTonal(onPressed: () => context.go('/settings'), icon: const Icon(Icons.settings_outlined)),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

// ---------------------------------------------------------------- hero

/// The shop's money in one number, where it sits, and today's three figures.
class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final money = ref.watch(moneyBucketsProvider);
    final today = ref.watch(todaySummaryProvider);
    final sync = ref.watch(syncStatusProvider).value;
    String m(num v) => Fmt.money(context, code, v);
    final total = money.total <= 0 ? 1 : money.total;
    int flex(int part) => part <= 0 ? 0 : math.max(1, (part * 1000 / total).round());

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4458C7), AppTheme.seed, AppTheme.navy]),
        boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: .28), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s('hero_total'), style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 13))),
            if (sync != null) _SyncChip(status: sync),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(m(money.total), style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                if (flex(money.eMoney) > 0) Expanded(flex: flex(money.eMoney), child: Container(color: AppTheme.blueprint)),
                if (flex(money.cash) > 0) ...[const SizedBox(width: 2), Expanded(flex: flex(money.cash), child: Container(color: const Color(0xFF5BE39B)))],
                if (flex(money.other) > 0) ...[const SizedBox(width: 2), Expanded(flex: flex(money.other), child: Container(color: const Color(0xFFFFC857)))],
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            _Legend(color: AppTheme.blueprint, label: s('total_float'), value: m(money.eMoney)),
            _Legend(color: const Color(0xFF5BE39B), label: s('cash_in_hand'), value: m(money.cash)),
            if (money.other != 0) _Legend(color: const Color(0xFFFFC857), label: s('other_money'), value: m(money.other)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              _HeroStat(label: s('today_commission'), value: m(today.commission.value)),
              _HeroDivider(),
              _HeroStat(label: s('today_tx'), value: bnDigits('${today.count}', code)),
              _HeroDivider(),
              _HeroStat(label: s('stat_expenses'), value: m(today.expenses.value)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11)),
        ]),
      );
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 28, color: Colors.white.withValues(alpha: .18));
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});
  final Color color;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 12)),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
}

/// Whether the shop's books on this phone are current — and, offline, that
/// nothing is lost: everything is on the phone and goes up when signal returns.
class _SyncChip extends ConsumerWidget {
  const _SyncChip({required this.status});
  final SyncStatus status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final (IconData icon, String label) = switch (status.state) {
      'ok' => (Icons.cloud_done_outlined, fill(s('synced_ago'), {'when': agoText(status.at!, code)})),
      'syncing' => (Icons.cloud_sync_outlined, s('syncing_now')),
      'read_only' => (Icons.lock_outline, s('sync_due')),
      'unpaired' => (Icons.link_off, s('sync_unpaired')),
      _ => (Icons.cloud_off_outlined, s('sync_offline')),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text, required this.onTap});
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
              Icon(Icons.chevron_right, color: color),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------- shortcuts

/// The eight jobs of an agent's day, one tap each.
///
/// Each opens the entry form already set to that kind, so "customer took ৳500
/// on credit" is: tap বাকি দেওয়া, type 500, pick the customer, save.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final actions = <(IconData, String, List<Color>, VoidCallback)>[
      (Icons.south_west_rounded, s('qa_cash_in'), const [Color(0xFF16A34A), Color(0xFF0F766E)], () => context.push('/add?type=cashIn')),
      (Icons.north_east_rounded, s('qa_cash_out'), const [Color(0xFFF97316), Color(0xFFDC2626)], () => context.push('/add?type=cashOut')),
      (Icons.handshake_outlined, s('qa_baki_give'), const [Color(0xFFE11D48), Color(0xFFBE185D)], () => context.push('/add?type=bakiGiven')),
      (Icons.payments_outlined, s('qa_baki_take'), const [Color(0xFF0EA5E9), Color(0xFF2563EB)], () => context.push('/add?type=bakiReceived')),
      (Icons.shopping_bag_outlined, s('qa_expense'), const [Color(0xFFF59E0B), Color(0xFFD97706)], () => context.push('/add?type=expense')),
      (Icons.lock_clock_outlined, s('qa_dayclose'), const [Color(0xFF6366F1), Color(0xFF4338CA)], () => context.go('/dayclose')),
      (Icons.insights_outlined, s('qa_reports'), const [Color(0xFF14B8A6), Color(0xFF0D9488)], () => context.go('/reports')),
      (Icons.local_shipping_outlined, s('qa_lift'), const [Color(0xFF8B5CF6), Color(0xFF6D28D9)], () => _liftSheet(context, ref)),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 8,
      childAspectRatio: .92,
      children: [
        for (final (icon, label, colors, onTap) in actions)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, maxLines: 2, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2)),
            ]),
          ),
      ],
    );
  }
}

/// Which wallet to ask the distributor to lift, with the amount the advisor
/// suggests already filled in.
Future<void> _liftSheet(BuildContext context, WidgetRef ref) async {
  final s = ref.s;
  final code = ref.read(localeProvider);
  final wallets = (ref.read(walletsProvider).value ?? const <Wallet>[]).where((w) => w.kind.isMfs).toList();
  final advice = ref.read(floatAdviceProvider);
  final hours = ref.read(shopHoursProvider).businessHours;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(title: Text(s('lift_sheet_title'), style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final w in wallets)
          () {
            final lift = advice[w.id]?.suggestedLift(hoursOfCover: hours) ?? Paisa.zero;
            return ListTile(
              leading: CircleAvatar(backgroundColor: AppTheme.walletColor(w.kind).withValues(alpha: .15), child: Icon(AppTheme.walletIcon(w.kind), color: AppTheme.walletColor(w.kind))),
              title: Text(w.nameIn(code)),
              subtitle: Text(lift.value > 0 ? Fmt.money(sheet, code, lift.value) : s('lift_none')),
              trailing: const Icon(Icons.chat_outlined, color: Color(0xFF25D366)),
              onTap: () async {
                Navigator.pop(sheet);
                await _askDistributor(context, ref, w, lift);
              },
            );
          }(),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<void> _askDistributor(BuildContext context, WidgetRef ref, Wallet wallet, Paisa lift) async {
  final s = ref.s;
  final code = ref.read(localeProvider);
  final number = await TopUpNumberTile.number();
  if (!context.mounted) return;
  if (number == null || number.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s('topup_number')), action: SnackBarAction(label: s('settings'), onPressed: () => context.go('/settings'))),
    );
    return;
  }
  final message = s('topup_message')
      .replaceAll('{wallet}', wallet.nameIn(code))
      .replaceAll('{amount}', lift.value > 0 ? Fmt.money(context, code, lift.value) : s('lift_amount_open'));
  final digits = number.replaceAll(RegExp(r'\D'), '');
  final intl = digits.startsWith('880') ? digits : '880${digits.replaceFirst(RegExp(r'^0'), '')}';
  await launchUrl(Uri.parse('https://wa.me/$intl?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication);
}

// ---------------------------------------------------------------- wallets

/// One wallet, in its operator's own colour.
///
/// The bar is the shop's business day, filled to how much of it this float
/// covers at the recent pace; its words say the same thing, so nobody reads a
/// colour. Recharge float and bank have no customer-driven drain to measure,
/// so they show a balance and nothing invented beside it.
class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.w, required this.balance, this.advice});
  final Wallet w;
  final Paisa balance;
  final FloatAdvice? advice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final hours = ref.watch(shopHoursProvider).businessHours;
    final base = AppTheme.walletColor(w.kind);
    final dark = Color.lerp(base, Colors.black, .35)!;
    final level = advice?.level ?? FloatLevel.ok;
    final hoursLeft = advice?.hoursLeft;
    final runway = advice == null ? null : _runwayText(s, code, advice!, hours);
    final share = hoursLeft == null ? 1.0 : (hoursLeft / math.max(1, hours)).clamp(0.03, 1.0);
    final warn = level == FloatLevel.low || level == FloatLevel.critical;

    return SizedBox(
      width: 236,
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/transactions?wallet=${w.id}'),
          child: Ink(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, dark])),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                  child: Icon(AppTheme.walletIcon(w.kind), color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(w.nameIn(code), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                if (warn)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99)),
                    child: Text(level == FloatLevel.critical ? s('critical_float') : s('low_float'), style: TextStyle(color: dark, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
              ]),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(Fmt.money(context, code, balance.value), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 10),
              if (runway != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: share, minHeight: 5, color: Colors.white, backgroundColor: Colors.white.withValues(alpha: .22)),
                ),
                const SizedBox(height: 6),
                Text(runway, style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 11, fontWeight: FontWeight.w600)),
              ] else if (w.accountNumber != null)
                Text(bnDigits(w.accountNumber!, code), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Hours while it matters today, working days after, "over a month" beyond.
String _runwayText(S s, String code, FloatAdvice a, int businessHours) {
  final h = a.hoursLeft;
  if (h == null) return s('steady');
  if (a.level == FloatLevel.critical && h == 0) return s('critical_float');
  if (h < businessHours) return '${s('runway')} ~${bnDigits(h.toStringAsFixed(1), code)} ${s('hours')}';
  final days = (h / math.max(1, businessHours)).round();
  if (days > 30) return s('runway_month');
  return fill(s('runway_days'), {'d': bnDigits('$days', code)});
}

// ---------------------------------------------------------------- trend

/// The last seven days of commission, today against yesterday.
class _TrendCard extends ConsumerWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final posted = ref.watch(postedProvider);
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 6; i >= 0; i--) d0.subtract(Duration(days: i))];
    final perDay = [
      for (final d in days)
        posted.where((t) => !t.occurredAt.isBefore(d) && t.occurredAt.isBefore(d.add(const Duration(days: 1)))).fold<int>(0, (sum, t) => sum + t.commission.value),
    ];
    final week = perDay.fold<int>(0, (a, b) => a + b);
    final today = perDay.last;
    final yesterday = perDay[5];
    final delta = yesterday == 0 ? null : ((today - yesterday) * 100 / yesterday).round();
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.teal.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.show_chart_rounded, color: Colors.teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(s('trend_title'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (delta != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: (delta >= 0 ? Colors.green : scheme.error).withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
                child: Text(
                  '${delta >= 0 ? '▲' : '▼'} ${bnDigits('${delta.abs()}', code)}% ${s('vs_yesterday')}',
                  style: TextStyle(color: delta >= 0 ? Colors.green.shade700 : scheme.error, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Fmt.money(context, code, week), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: Colors.teal.shade700)),
              Text(s('trend_week'), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(width: 16),
            Expanded(child: SizedBox(height: 56, child: CustomPaint(painter: _Spark(perDay, Colors.teal)))),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final d in days)
              Text(bnDigits(DateFormat('E', code == 'bn' ? 'bn' : 'en').format(d), code), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}

class _Spark extends CustomPainter {
  _Spark(this.values, this.color);
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final peak = values.reduce(math.max);
    final top = peak <= 0 ? 1 : peak;
    final dx = values.length == 1 ? 0.0 : size.width / (values.length - 1);
    final points = [for (var i = 0; i < values.length; i++) Offset(i * dx, size.height - (values[i] / top) * (size.height - 6) - 3)];

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final mid = (a.dx + b.dx) / 2;
      line.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)]).createShader(Offset.zero & size));
    canvas.drawPath(line, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(points.last, 4, Paint()..color = color);
    canvas.drawCircle(points.last, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _Spark old) => old.values != values || old.color != color;
}

// ---------------------------------------------------------------- baki

/// Who owes the shop, the largest first, one tap to remind.
class _BakiCard extends ConsumerWidget {
  const _BakiCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final dues = ref.watch(receivablesProvider);
    final customers = ref.watch(customersProvider).value ?? const <Customer>[];
    final owing = [
      for (final c in customers)
        if ((dues[c.id]?.value ?? 0) > 0) (c, dues[c.id]!),
    ]..sort((a, b) => b.$2.value.compareTo(a.$2.value));
    final total = owing.fold<int>(0, (sum, e) => sum + e.$2.value);

    return _MiniCard(
      icon: Icons.handshake_outlined,
      color: const Color(0xFFE11D48),
      title: s('baki_widget'),
      value: Fmt.money(context, code, total),
      onTap: () => context.go('/customers'),
      child: owing.isEmpty
          ? Text(s('baki_none'), style: Theme.of(context).textTheme.bodySmall)
          : Column(children: [
              for (final (c, due) in owing.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
                    Text(Fmt.money(context, code, due.value), style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
    );
  }
}

// ---------------------------------------------------------------- day close

/// Is today's drawer counted, and was yesterday's?
class _DayCloseCard extends ConsumerWidget {
  const _DayCloseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final closes = ref.watch(dayClosesProvider).value ?? const <DayClose>[];
    final posted = ref.watch(postedProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    bool closedOn(DateTime d) => closes.any((c) => c.date.year == d.year && c.date.month == d.month && c.date.day == d.day);
    bool tradedOn(DateTime d) => posted.any((t) => !t.occurredAt.isBefore(d) && t.occurredAt.isBefore(d.add(const Duration(days: 1))));

    final (String line, bool ok) = closedOn(today)
        ? (s('dayclose_done'), true)
        : tradedOn(yesterday) && !closedOn(yesterday)
            ? (s('dayclose_yesterday_open'), false)
            : (s('dayclose_pending'), true);

    return _MiniCard(
      icon: Icons.lock_clock_outlined,
      color: const Color(0xFF6366F1),
      title: s('dayclose'),
      value: closedOn(today) ? '✓' : s('dayclose_go'),
      onTap: () => context.go('/dayclose'),
      child: Text(line, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ok ? null : Theme.of(context).colorScheme.error, fontWeight: ok ? null : FontWeight.w600)),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.icon, required this.color, required this.title, required this.value, required this.onTap, required this.child});
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(height: 6),
              child,
            ]),
          ),
        ),
      );
}
