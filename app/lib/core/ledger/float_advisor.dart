import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/money.dart';

class FloatAdvice {
  const FloatAdvice({required this.walletId, required this.balance, required this.burnPerHour, required this.hoursLeft, required this.level});
  final String walletId;
  final Paisa balance;
  /// Average net outflow per business hour over the look-back window.
  final Paisa burnPerHour;
  /// Null when the wallet is not draining.
  final double? hoursLeft;
  final FloatLevel level;

  /// How much float to ask the distributor for, to last a full trading day.
  ///
  /// Rounded UP to the nearest thousand taka because that is how lifting is
  /// actually asked for: nobody requests 7,431 taka. Zero when the wallet is
  /// not draining or already holds more than a day of cover, which is the
  /// signal to hide the request button rather than offer a request for nothing.
  Paisa suggestedLift({int hoursOfCover = 12}) {
    if (burnPerHour.value <= 0) return Paisa.zero;
    final need = burnPerHour.value * hoursOfCover - balance.value;
    if (need <= 0) return Paisa.zero;
    const step = 1000 * 100;
    return Paisa(((need + step - 1) ~/ step) * step);
  }
}

enum FloatLevel { ok, watch, low, critical }

/// Predicts when a wallet will run dry based on recent net outflow.
class FloatAdvisor {
  const FloatAdvisor({this.lookBack = const Duration(days: 7), this.businessHoursPerDay = 12, this.lowFloatHours = 6});
  final Duration lookBack;
  /// The shop's trading day, from its settings. Twelve until a shop says otherwise.
  final int businessHoursPerDay;
  /// Below this many hours of cover a wallet is "low" — the shop's own
  /// threshold, the same one the portal and the bell use.
  final int lowFloatHours;

  FloatAdvice advise({
    required Wallet wallet,
    required Paisa balance,
    required Iterable<Transaction> txs,
    required DateTime now,
  }) {
    final since = now.subtract(lookBack);
    var out = 0;
    var inn = 0;
    for (final t in txs) {
      if (t.walletId != wallet.id || t.occurredAt.isBefore(since) || t.status == TxStatus.voided) continue;
      // Exclude distributor top-ups so the burn reflects customer demand.
      if (t.type == TxType.b2bIn || t.type == TxType.b2bOut || t.type == TxType.capital) continue;
      if (t.type.debitsWallet) {
        out += t.amount.value;
      } else {
        inn += t.amount.value;
      }
    }
    final days = (now.difference(since).inHours / 24).clamp(1, 365);
    final netPerHour = ((out - inn) / days / businessHoursPerDay).round();
    final burn = Paisa(netPerHour > 0 ? netPerHour : 0);

    /*
     * A wallet at or below zero has no runway.
     *
     * Without this the division produces a NEGATIVE hours-left, so a wallet
     * 51,000 taka overdrawn reads "runs out in about -41.2 hours" — which is
     * meaningless, and worse, sorts as the least urgent wallet on the board.
     * Zero is the honest answer and it puts the row where it belongs. The
     * server's `floatAdvice` makes the same call for the same reason.
     */
    final empty = balance.value <= 0;
    double? hours;
    if (empty) {
      hours = 0;
    } else if (burn.value > 0) {
      hours = balance.value / burn.value;
    }

    final level = empty
        ? FloatLevel.critical
        : hours == null
            ? FloatLevel.ok
            : hours < 2
                ? FloatLevel.critical
                : hours < lowFloatHours
                    ? FloatLevel.low
                    : hours < businessHoursPerDay
                        ? FloatLevel.watch
                        : FloatLevel.ok;
    return FloatAdvice(walletId: wallet.id, balance: balance, burnPerHour: burn, hoursLeft: hours, level: level);
  }
}
