import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/money.dart';

class PeriodSummary {
  const PeriodSummary({
    required this.from,
    required this.to,
    required this.commission,
    required this.fees,
    required this.expenses,
    required this.drawings,
    required this.capital,
    required this.byType,
    required this.byWallet,
    required this.count,
  });
  final DateTime from;
  final DateTime to;
  final Paisa commission;
  final Paisa fees;
  final Paisa expenses;
  final Paisa drawings;
  final Paisa capital;
  final Map<TxType, Paisa> byType;
  final Map<String, Paisa> byWallet; // commission per wallet
  final int count;

  Paisa get grossProfit => commission - fees;
  Paisa get netProfit => grossProfit - expenses;
}

class Reports {
  const Reports();

  PeriodSummary summarize(Iterable<Transaction> txs, {required DateTime from, required DateTime to}) {
    var commission = 0, fees = 0, expenses = 0, drawings = 0, capital = 0, count = 0;
    final byType = <TxType, int>{};
    final byWallet = <String, int>{};
    for (final t in txs) {
      if (t.status == TxStatus.voided) continue;
      if (t.occurredAt.isBefore(from) || !t.occurredAt.isBefore(to)) continue;
      count++;
      commission += t.commission.value;
      fees += t.fee.value;
      byType[t.type] = (byType[t.type] ?? 0) + t.amount.value;
      byWallet[t.walletId] = (byWallet[t.walletId] ?? 0) + t.commission.value;
      switch (t.type) {
        case TxType.expense:
          expenses += t.amount.value;
        case TxType.drawing:
          drawings += t.amount.value;
        case TxType.capital:
          capital += t.amount.value;
        default:
          break;
      }
    }
    return PeriodSummary(
      from: from,
      to: to,
      commission: Paisa(commission),
      fees: Paisa(fees),
      expenses: Paisa(expenses),
      drawings: Paisa(drawings),
      capital: Paisa(capital),
      byType: byType.map((k, v) => MapEntry(k, Paisa(v))),
      byWallet: byWallet.map((k, v) => MapEntry(k, Paisa(v))),
      count: count,
    );
  }

  /// Outstanding baki per customer (positive = customer owes the agent).
  Map<String, Paisa> receivables(Iterable<Transaction> txs) {
    final out = <String, int>{};
    for (final t in txs) {
      if (t.status == TxStatus.voided || t.customerId == null) continue;
      if (t.type == TxType.bakiGiven) out[t.customerId!] = (out[t.customerId!] ?? 0) + t.amount.value;
      if (t.type == TxType.bakiReceived) out[t.customerId!] = (out[t.customerId!] ?? 0) - t.amount.value;
    }
    return out.map((k, v) => MapEntry(k, Paisa(v)));
  }
}
