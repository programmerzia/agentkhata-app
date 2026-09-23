import '../domain/enums.dart';
import '../domain/money.dart';

/// Output of [MessageParser]. Either a transaction candidate or a reason it
/// was not one.
class ParsedMessage {
  const ParsedMessage({
    required this.status,
    this.operator,
    this.type,
    this.amount,
    this.fee,
    this.commission,
    this.balanceAfter,
    this.counterparty,
    this.trxId,
    this.occurredAt,
    this.confidence = 0,
    this.reason,
    this.billerName,
    this.billerAccount,
  });

  const ParsedMessage.ignored(String reason)
      : this(status: ParseStatus.ignored, reason: reason);

  const ParsedMessage.unparsed([String? reason])
      : this(status: ParseStatus.unparsed, reason: reason);

  /// Who the bill was paid to, as the operator wrote it ("NESCOPre").
  final String? billerName;

  /// The customer's account with that biller — a prepaid meter number, a
  /// postpaid account, a WASA bill number. What the agent is asked for when a
  /// customer comes back saying the recharge never arrived.
  final String? billerAccount;

  final ParseStatus status;
  final WalletKind? operator;
  final TxType? type;
  final Paisa? amount;
  final Paisa? fee;
  final Paisa? commission;
  final Paisa? balanceAfter;
  final String? counterparty;
  final String? trxId;
  final DateTime? occurredAt;

  /// 0..1. Below [MessageParser.autoPostThreshold] goes to review.
  final double confidence;
  final String? reason;

  bool get isTransaction => status == ParseStatus.parsed || status == ParseStatus.suspicious;

  ParsedMessage copyWith({ParseStatus? status, String? reason}) => ParsedMessage(
        status: status ?? this.status,
        operator: operator,
        type: type,
        amount: amount,
        fee: fee,
        commission: commission,
        balanceAfter: balanceAfter,
        counterparty: counterparty,
        trxId: trxId,
        occurredAt: occurredAt,
        confidence: confidence,
        reason: reason ?? this.reason,
      );

  @override
  String toString() =>
      'ParsedMessage($status $operator $type amt=$amount fee=$fee comm=$commission bal=$balanceAfter cp=$counterparty trx=$trxId at=$occurredAt conf=$confidence${reason == null ? '' : ' reason=$reason'})';
}
