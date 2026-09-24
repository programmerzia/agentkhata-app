import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/money.dart';

/// Account identifiers in the double-entry view of the books.
class Account {
  const Account._(this.id);
  final String id;

  static Account wallet(String walletId) => Account._('wallet:$walletId');
  static const commissionIncome = Account._('income:commission');
  static const feeExpense = Account._('expense:fee');
  static Account expense([String category = 'general']) => Account._('expense:$category');
  static const ownerEquity = Account._('equity:owner');
  static Account receivable(String customerId) => Account._('receivable:$customerId');
  static const customerClearing = Account._('clearing:customer');
  static const distributorClearing = Account._('clearing:distributor');

  bool get isWallet => id.startsWith('wallet:');
  String? get walletId => isWallet ? id.substring(7) : null;

  @override
  bool operator ==(Object other) => other is Account && other.id == id;
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() => id;
}

class Posting {
  const Posting(this.account, this.delta);
  final Account account;
  final Paisa delta;
  @override
  String toString() => '$account ${delta.format()}';
}

/// Converts a transaction into balanced postings.
///
/// Conventions (agent's point of view):
/// * cashIn: customer hands cash, agent's e-wallet goes down → cash +, wallet −.
/// * cashOut: agent hands cash, e-wallet goes up → cash −, wallet +.
/// * Commission earned is added to the wallet (operators credit it to the
///   agent wallet) and booked as income. Fees paid reduce the wallet.
/// * b2bIn: distributor gives e-money, agent pays cash → wallet +, cash −.
class Ledger {
  const Ledger({required this.cashWalletId});
  final String cashWalletId;

  List<Posting> postingsFor(Transaction t) {
    if (t.status == TxStatus.voided) return const [];
    final w = Account.wallet(t.walletId);
    final cash = Account.wallet(cashWalletId);
    final other = t.counterWalletId == null ? cash : Account.wallet(t.counterWalletId!);
    final a = t.amount;
    final p = <Posting>[];

    switch (t.type) {
      case TxType.cashIn:
        p.addAll([Posting(w, -a), Posting(cash, a)]);
      case TxType.cashOut:
        p.addAll([Posting(w, a), Posting(cash, -a)]);
      case TxType.sendMoney:
      case TxType.billPay:
        // Customer pays cash for the service; if it was the agent's own money the
        // user records it as cashMove instead.
        p.addAll([Posting(w, -a), Posting(cash, a)]);
      case TxType.receiveMoney:
      case TxType.payment:
        p.addAll([Posting(w, a), Posting(Account.customerClearing, -a)]);
      case TxType.b2bIn:
        p.addAll([Posting(w, a), Posting(other, -a)]);
      case TxType.b2bOut:
        p.addAll([Posting(w, -a), Posting(other, a)]);
      case TxType.recharge:
        p.addAll([Posting(w, -a), Posting(cash, a)]);
      case TxType.expense:
        p.addAll([Posting(w, -a), Posting(Account.expense(t.note ?? 'general'), a)]);
      case TxType.drawing:
        p.addAll([Posting(w, -a), Posting(Account.ownerEquity, a)]);
      case TxType.capital:
        p.addAll([Posting(w, a), Posting(Account.ownerEquity, -a)]);
      case TxType.cashMove:
        p.addAll([Posting(w, -a), Posting(other, a)]);
      case TxType.bakiGiven:
        p.addAll([Posting(w, -a), Posting(Account.receivable(t.customerId ?? 'unknown'), a)]);
      case TxType.bakiReceived:
        p.addAll([Posting(w, a), Posting(Account.receivable(t.customerId ?? 'unknown'), -a)]);
      case TxType.adjustment:
        p.addAll([Posting(w, a), Posting(Account.ownerEquity, -a)]);
    }

    if (t.commission.value != 0) {
      // A charge taken in paper money goes to the drawer — unless the entry
      // already names another wallet as its other side (a B2B lift or a
      // transfer to a chosen account). The portal's ledger makes the same
      // exception; the shared fixtures pin it.
      final namesOther = t.counterWalletId != null &&
          (t.type == TxType.b2bIn || t.type == TxType.b2bOut || t.type == TxType.cashMove);
      final lands = t.commissionInCash && !namesOther ? cash : w;
      p.addAll([Posting(lands, t.commission), Posting(Account.commissionIncome, -t.commission)]);
    }
    if (t.fee.value != 0) {
      p.addAll([Posting(w, -t.fee), Posting(Account.feeExpense, t.fee)]);
    }
    assert(p.fold<int>(0, (s, x) => s + x.delta.value) == 0, 'postings must balance');
    return p;
  }

  /// Balance of every wallet after applying [txs] on top of opening balances.
  Map<String, Paisa> balances(Iterable<Wallet> wallets, Iterable<Transaction> txs, {DateTime? until}) {
    final out = <String, Paisa>{for (final w in wallets) w.id: w.openingBalance};
    for (final t in txs) {
      if (until != null && t.occurredAt.isAfter(until)) continue;
      for (final p in postingsFor(t)) {
        final id = p.account.walletId;
        if (id == null) continue;
        out[id] = (out[id] ?? Paisa.zero) + p.delta;
      }
    }
    return out;
  }
}
