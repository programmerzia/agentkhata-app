import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../../sync/sync_providers.dart';

/// Which of the shop's wallets this phone records.
final capturesProvider = FutureProvider<Set<String>?>((ref) async {
  // Re-read whenever the wallet list changes: joining a shop brings new ones.
  ref.watch(walletsProvider);
  return ref.read(repositoryProvider).captures();
});

/// "This phone records bKash and Nagad; the other phone does Upay."
///
/// One switch per operator wallet. Turning one off here does not touch the
/// wallet — it stays in the books, and the phone that runs that operator's
/// app keeps recording it — it only stops THIS phone posting into it, which is
/// what stops the agent's personal bKash notifications reaching the shop's
/// float from a phone that should not be capturing bKash at all.
class CapturesEditor extends ConsumerWidget {
  const CapturesEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where((w) => w.kind.isMfs)
        .toList();
    final captures = ref.watch(capturesProvider).value;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(s('captures_sub'), style: Theme.of(context).textTheme.bodySmall),
      ),
      for (final w in wallets)
        SwitchListTile(
          secondary: Icon(AppTheme.walletIcon(w.kind), color: AppTheme.walletColor(w.kind)),
          title: Text(code == 'bn' ? w.kind.labelBn : w.label),
          subtitle: w.accountNumber == null ? null : Text(bnDigits(w.accountNumber!, code)),
          value: captures == null || captures.contains(w.id),
          onChanged: (on) async {
            final repo = ref.read(repositoryProvider);
            // "Everything" becomes an explicit list the first time one is turned
            // off, so the choice survives the wallets list growing later.
            final current = captures ?? wallets.map((x) => x.id).toSet();
            final next = {...current};
            on ? next.add(w.id) : next.remove(w.id);
            await repo.setCaptures(next);
            await repo.setMeta('last_device_report', '');
            ref.invalidate(capturesProvider);
            ref.read(syncServiceProvider)?.scheduleSync(const Duration(seconds: 1));
          },
        ),
    ]);
  }
}
