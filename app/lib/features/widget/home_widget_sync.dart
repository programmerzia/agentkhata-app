import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';

/// What the launcher widget shows, published from the app that knows it.
///
/// ## Why the app pushes instead of the widget pulling
///
/// A widget provider runs in a broadcast receiver with no Flutter engine and
/// about ten seconds of life. It cannot open the ledger, and it must not try.
/// So every string it paints — already grouped in the Bangladeshi 12,34,567
/// style, already in Bangla numerals if that is the chosen language — is
/// written here and read there.
///
/// ## Why it is a provider rather than a call after each save
///
/// The numbers are derived from the transaction stream, and the things that
/// change them are many: a manual entry, an auto-captured SMS, a sync pull, a
/// void. Watching the derived providers catches all of them, including the ones
/// that arrive while the agent is looking at a different screen.
final homeWidgetSyncProvider = Provider<void>((ref) {
  final code = ref.watch(localeProvider);
  final wallets = ref.watch(walletsProvider).value ?? [];
  final advice = ref.watch(floatAdviceProvider);
  final today = ref.watch(todaySummaryProvider);
  final unsorted = ref.watch(unsortedProvider).value ?? [];
  final pending = ref.watch(pendingCountProvider);
  final money = ref.watch(moneyBucketsProvider);

  // Nothing to say before the wallets have loaded, and saying it would blank a
  // widget that currently holds correct numbers.
  if (wallets.isEmpty) return;

  // The same buckets as the home screen and the portal: a widget that added
  // up "float" its own way would disagree with the app it opens.
  final float = money.eMoney;
  final cash = money.cash;
  final inbox = unsorted.length + pending;

  final bn = code == 'bn';
  final low = wallets
      .where((w) => w.kind != WalletKind.cash)
      .where((w) {
        final level = advice[w.id]?.level;
        return level == FloatLevel.low || level == FloatLevel.critical;
      })
      .map((w) => w.nameIn(bn ? 'bn' : 'en'))
      .toList();

  final tr = S(code);
  final data = <String, String>{
    'shop': tr('app'),
    // Date as well as time: the widget only refreshes when the phone captures
    // or the app runs, and "14:05" on yesterday's numbers passes for today.
    'updated': bnDigits(_stamp(DateTime.now(), code), code),
    'floatLabel': tr('total_float'),
    'float': Fmt.moneyOf(code, float),
    'cashLabel': tr('cash_in_hand'),
    'cash': Fmt.moneyOf(code, cash),
    'today':
        '${tr('today_commission')} ${Fmt.moneyOf(code, today.commission.value)}  •  ${tr('today_tx')} ${bnDigits('${today.count}', code)}',
    'alert': low.isEmpty ? '' : '${tr('low_float')}: ${low.join(', ')}',
    'addLabel': '+ ${tr('add')}',
    // Unsorted messages AND entries waiting for review — the same count as the
    // inbox badge on the home screen.
    'inboxLabel': inbox == 0 ? tr('unsorted') : '${tr('unsorted')} (${bnDigits('$inbox', code)})',
  };

  // Fire and forget: a launcher that has no widget placed yet, or a platform
  // that has none at all, must not turn into an error on the dashboard.
  unawaited(() async {
    try {
      for (final entry in data.entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(name: 'HomeScreenWidget', androidName: 'HomeScreenWidget');
    } catch (error) {
      debugPrint('home widget update skipped: $error');
    }
  }());
});

String _stamp(DateTime at, String code) =>
    '${DateFormat('d MMM', code == 'bn' ? 'bn' : 'en').format(at)} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Where a tap on the widget lands.
///
/// The widget's buttons carry `agentkhata://widget/<screen>` rather than a bare
/// launch, so the agent arrives on the screen they aimed at instead of the
/// dashboard plus three taps. Both entry points matter: `widgetClicked` for a
/// running app, `initiallyLaunchedFromHomeWidget` for a cold start, where the
/// stream has already fired before anything listens.
final homeWidgetRouteProvider = Provider<void>((ref) {
  void go(Uri? uri) {
    if (uri == null || uri.scheme != 'agentkhata' || uri.host != 'widget') return;
    final target = switch (uri.pathSegments.isEmpty ? '' : uri.pathSegments.first) {
      'add' => '/add',
      'unsorted' => '/unsorted',
      _ => '/',
    };
    ref.read(routerProvider).go(target);
  }

  final subscription = HomeWidget.widgetClicked.listen(go);
  ref.onDispose(subscription.cancel);
  unawaited(HomeWidget.initiallyLaunchedFromHomeWidget().then(go).catchError((_) {}));
});
