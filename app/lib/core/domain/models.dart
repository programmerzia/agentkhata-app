import 'enums.dart';
import 'money.dart';

class Wallet {
  const Wallet({
    required this.id,
    required this.kind,
    required this.label,
    this.accountNumber,
    this.isActive = true,
    this.openingBalance = Paisa.zero,
    required this.openingAt,
  });
  final String id;
  final WalletKind kind;
  final String label;
  final String? accountNumber;
  final bool isActive;
  final Paisa openingBalance;
  final DateTime openingAt;
}

class Transaction {
  const Transaction({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    this.fee = Paisa.zero,
    this.commission = Paisa.zero,
    this.counterparty,
    this.trxId,
    this.balanceAfter,
    required this.occurredAt,
    this.source = TxSource.manual,
    this.rawMessageId,
    this.note,
    this.customerId,
    this.counterWalletId,
    this.billerName,
    this.billerAccount,
    this.billerToken,
    this.status = TxStatus.posted,
  });
  final String id;
  final String walletId;
  final TxType type;
  final Paisa amount;
  final Paisa fee;
  final Paisa commission;
  final String? counterparty;
  final String? trxId;
  final Paisa? balanceAfter;
  final DateTime occurredAt;
  final TxSource source;
  final String? rawMessageId;
  final String? note;
  final String? customerId;

  /// For cashMove and b2b: the other wallet involved (usually cash).
  final String? counterWalletId;

  /// A bill's biller ("NESCOPre"), the customer's account with them (a prepaid
  /// meter number), and the token the biller sends back, when it arrives.
  final String? billerName;
  final String? billerAccount;
  final String? billerToken;
  final TxStatus status;

  Transaction copyWith({
    Paisa? commission,
    TxStatus? status,
    String? customerId,
    String? note,
    String? counterWalletId,
    String? billerToken,
  }) =>
      Transaction(
        id: id,
        walletId: walletId,
        type: type,
        amount: amount,
        fee: fee,
        commission: commission ?? this.commission,
        counterparty: counterparty,
        trxId: trxId,
        balanceAfter: balanceAfter,
        occurredAt: occurredAt,
        source: source,
        rawMessageId: rawMessageId,
        note: note ?? this.note,
        customerId: customerId ?? this.customerId,
        counterWalletId: counterWalletId ?? this.counterWalletId,
        billerName: billerName,
        billerAccount: billerAccount,
        billerToken: billerToken ?? this.billerToken,
        status: status ?? this.status,
      );
}

class RawMessage {
  const RawMessage({
    required this.id,
    required this.source,
    required this.sender,
    this.packageName,
    required this.body,
    required this.receivedAt,
    this.parseStatus = ParseStatus.unparsed,
    this.parsedTransactionId,
  });
  final String id;
  final TxSource source;
  final String sender;
  final String? packageName;
  final String body;
  final DateTime receivedAt;
  final ParseStatus parseStatus;
  final String? parsedTransactionId;
}

class Customer {
  const Customer({required this.id, required this.name, this.phone, this.note});
  final String id;
  final String name;
  final String? phone;
  final String? note;
}

class DayClose {
  const DayClose({
    required this.id,
    required this.date,
    required this.walletId,
    required this.expected,
    required this.actual,
    this.note,
    required this.closedAt,
  });
  final String id;
  final DateTime date;
  final String walletId;
  final Paisa expected;
  final Paisa actual;
  final String? note;
  final DateTime closedAt;
  Paisa get difference => actual - expected;
}

extension WalletName on Wallet {
  /// What the agent calls this account. A stock name ("bKash") becomes the
  /// operator in their language plus the number's last digits, so two bKash
  /// accounts never read the same; a name the agent chose is kept as typed.
  String nameIn(String code) {
    final stock = label == kind.label || label == kind.labelBn;
    if (!stock) return label;
    final base = code == 'bn' ? kind.labelBn : kind.label;
    final n = accountNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
    return n.length >= 4 ? '$base ··${n.substring(n.length - 4)}' : base;
  }
}
