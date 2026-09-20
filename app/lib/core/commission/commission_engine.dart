import '../domain/enums.dart';
import '../domain/money.dart';

enum RateMode { perThousand, percent, flat, slab }

class Slab {
  const Slab({required this.upTo, required this.value});
  /// Upper bound of this slab in paisa, inclusive. Null = open-ended.
  final Paisa? upTo;
  final Paisa value;
}

/// What the agent earns, per operator and per kind of transaction.
///
/// ## Why the rate is parts per million
///
/// A commission is `amount x rate`, and the two ways operators quote a rate —
/// "4.10 taka per thousand" and "2.75 percent" — are the same ratio written
/// differently. Storing the quoted number with its unit means every reader has
/// to know which unit a row is in before the number means anything, and one
/// reader eventually will not.
///
/// So the ratio is normalised to an integer: 4.10 per thousand is 4,100 ppm
/// and 2.75 percent is 27,500 ppm. [mode] survives only to render it back in
/// the unit the agent was quoted in, which is what they compare against their
/// distributor's SMS.
///
/// Integer rather than double because this number is multiplied by money.
/// The server enforces the same rule, and the shared fixtures prove the two
/// implementations agree.
class CommissionRule {
  const CommissionRule({
    required this.walletKind,
    required this.txType,
    required this.mode,
    this.ratePpm = 0,
    this.flatPoisha,
    this.slabs = const [],
    this.effectiveFrom,
  });
  final WalletKind walletKind;
  final TxType txType;

  /// Only how the rate is displayed and entered; the maths uses [ratePpm].
  final RateMode mode;

  /// The ratio in parts per million. 4.10 per thousand is 4100.
  final int ratePpm;

  /// Used only when [mode] is [RateMode.flat].
  final int? flatPoisha;
  final List<Slab> slabs;
  final DateTime? effectiveFrom;

  /// The number the agent was quoted, for display and editing.
  double get quoted => switch (mode) {
        RateMode.perThousand => ratePpm / 1000,
        RateMode.percent => ratePpm / 10000,
        RateMode.flat => (flatPoisha ?? 0) / 100,
        RateMode.slab => 0,
      };

  /// The stored ratio, from a number typed in the unit [mode] names.
  static int ppmFrom(RateMode mode, double quoted) => switch (mode) {
        RateMode.perThousand => (quoted * 1000).round(),
        RateMode.percent => (quoted * 10000).round(),
        _ => 0,
      };

  Paisa compute(Paisa amount) {
    switch (mode) {
      case RateMode.perThousand:
      case RateMode.percent:
        return Paisa(_divideRoundHalfAwayFromZero(amount.value * ratePpm, 1000000));
      case RateMode.flat:
        return Paisa(flatPoisha ?? 0);
      case RateMode.slab:
        for (final s in slabs) {
          if (s.upTo == null || amount.value <= s.upTo!.value) return s.value;
        }
        return Paisa.zero;
    }
  }
}

/// Rounds half away from zero, unlike Dart's `round()` on negatives.
///
/// Commission is never negative, but this is the one place rounding happens
/// and a rule that is asymmetric about zero is a rule that drifts. The server
/// does the same, and the shared fixtures would fail if either changed.
int _divideRoundHalfAwayFromZero(int numerator, int denominator) {
  final negative = numerator < 0;
  final abs = negative ? -numerator : numerator;
  final rounded = (abs + denominator ~/ 2) ~/ denominator;
  return negative ? -rounded : rounded;
}

/// Computes agent earnings. Operator-stated commission (from the SMS "Comm Tk")
/// always wins over the rule table because it is the ground truth.
class CommissionEngine {
  CommissionEngine([List<CommissionRule>? rules]) : rules = rules ?? defaultRules;

  final List<CommissionRule> rules;

  /// Default public rates as of 2026. Verify with each operator's current
  /// agent circular and adjust in Settings; all values are editable.
  static final List<CommissionRule> defaultRules = [
    // bKash agent: 4.10 taka per 1,000 on cash-in and cash-out.
    const CommissionRule(walletKind: WalletKind.bkash, txType: TxType.cashIn, mode: RateMode.perThousand, ratePpm: 4100),
    const CommissionRule(walletKind: WalletKind.bkash, txType: TxType.cashOut, mode: RateMode.perThousand, ratePpm: 4100),
    // Nagad uddokta.
    const CommissionRule(walletKind: WalletKind.nagad, txType: TxType.cashIn, mode: RateMode.perThousand, ratePpm: 4100),
    const CommissionRule(walletKind: WalletKind.nagad, txType: TxType.cashOut, mode: RateMode.perThousand, ratePpm: 4100),
    // Rocket (DBBL).
    const CommissionRule(walletKind: WalletKind.rocket, txType: TxType.cashIn, mode: RateMode.perThousand, ratePpm: 4170),
    const CommissionRule(walletKind: WalletKind.rocket, txType: TxType.cashOut, mode: RateMode.perThousand, ratePpm: 4170),
    // Upay.
    const CommissionRule(walletKind: WalletKind.upay, txType: TxType.cashIn, mode: RateMode.perThousand, ratePpm: 4100),
    const CommissionRule(walletKind: WalletKind.upay, txType: TxType.cashOut, mode: RateMode.perThousand, ratePpm: 4100),
    // Mobile recharge margin, typical retailer share 2.75%.
    const CommissionRule(walletKind: WalletKind.recharge, txType: TxType.recharge, mode: RateMode.percent, ratePpm: 27500),
    const CommissionRule(walletKind: WalletKind.bkash, txType: TxType.recharge, mode: RateMode.percent, ratePpm: 27500),
    const CommissionRule(walletKind: WalletKind.nagad, txType: TxType.recharge, mode: RateMode.percent, ratePpm: 27500),
  ];

  CommissionRule? ruleFor(WalletKind kind, TxType type, {DateTime? at}) {
    CommissionRule? best;
    for (final r in rules) {
      if (r.walletKind != kind || r.txType != type) continue;
      if (at != null && r.effectiveFrom != null && r.effectiveFrom!.isAfter(at)) continue;
      if (best == null || (r.effectiveFrom ?? DateTime(2000)).isAfter(best.effectiveFrom ?? DateTime(2000))) {
        best = r;
      }
    }
    return best;
  }

  Paisa commissionFor({
    required WalletKind kind,
    required TxType type,
    required Paisa amount,
    Paisa? statedByOperator,
    DateTime? at,
  }) {
    if (statedByOperator != null && statedByOperator.value > 0) return statedByOperator;
    return ruleFor(kind, type, at: at)?.compute(amount) ?? Paisa.zero;
  }
}
