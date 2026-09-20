import '../domain/enums.dart';
import '../domain/money.dart';
import 'operator_detector.dart';
import 'parsed_message.dart';

/// Turns operator SMS / notification text into a [ParsedMessage].
///
/// Design goals:
/// * Never read secrets: OTP / PIN messages are dropped before anything else.
/// * Tolerant: bKash, Nagad, Rocket, Upay and Tap all phrase things slightly
///   differently ("Balance Tk", "Bal Tk", "Balance: Tk", "TrxID", "TxnID",
///   "TxnId"). Field extractors are keyword-anchored, not full-line regexes,
///   so small format changes degrade to "pending review" rather than a miss.
/// * Explainable: every non-transaction result carries a reason.
class MessageParser {
  const MessageParser();

  static const double autoPostThreshold = 0.85;

  static final RegExp _secret = RegExp(
    r'\b(otp|one[- ]time|verification code|pin|password|passcode)\b',
    caseSensitive: false,
  );
  static final RegExp _failure = RegExp(
    r'\b(failed|unsuccessful|declined|reversed|cancel+ed|insufficient|request(ed)?|pending|will be|do not share|never share)\b',
    caseSensitive: false,
  );
  static final RegExp _promo = RegExp(
    r'(offer|cashback|bonus|congratulations|win|discount|campaign|apply now|download)',
    caseSensitive: false,
  );

  static final RegExp _money = RegExp(r'(?:tk\.?|৳|bdt)\s*([\d,০-৯]+(?:\.\d{1,2})?)', caseSensitive: false);
  static final RegExp _balance = RegExp(
      r'(?:balance|bal|new balance|available balance|current balance|a/c balance)\s*(?:is|:)?\s*(?:tk\.?|৳|bdt)?\s*([\d,০-৯]+(?:\.\d{1,2})?)',
      caseSensitive: false);
  static final RegExp _fee = RegExp(r'(?:fee|charge)\s*:?\s*(?:tk\.?|৳|bdt)?\s*([\d,০-৯]+(?:\.\d{1,2})?)', caseSensitive: false);
  static final RegExp _comm = RegExp(r'(?:comm(?:ission)?)\s*:?\s*(?:tk\.?|৳|bdt)?\s*([\d,০-৯]+(?:\.\d{1,2})?)', caseSensitive: false);
  static final RegExp _trx = RegExp(
      r'(?:trx\s?id|txn\s?id|transaction\s?id|trans\s?id|ref(?:erence)?(?:\s?no)?)\s*[:#]?\s*([A-Z0-9]{6,20})',
      caseSensitive: false);
  static final RegExp _phone = RegExp(r'(?<!\d)(?:\+?88)?(01\d{9}(?:\d{1,2})?)(?!\d)');
  static final RegExp _dateTime = RegExp(
      r'(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\s*,?\s*(?:at\s*)?(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?',
      caseSensitive: false);

  ParsedMessage parse(String body, {required String sender, String? packageName, DateTime? receivedAt}) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return const ParsedMessage.ignored('empty');
    if (_secret.hasMatch(text)) return const ParsedMessage.ignored('secret');

    final senderOp = OperatorDetector.fromSender(sender, packageName: packageName);
    final bodyOp = OperatorDetector.fromBody(text);
    final operator = senderOp ?? bodyOp;
    if (operator == null) return const ParsedMessage.ignored('not an operator message');

    if (_failure.hasMatch(text)) return const ParsedMessage.ignored('not a completed transaction');

    if (_promo.hasMatch(text) && !_trx.hasMatch(text)) return const ParsedMessage.ignored('promo');

    final type = _detectType(text);
    if (type == null) {
      return ParsedMessage(status: ParseStatus.unparsed, operator: operator, reason: 'unknown transaction type');
    }

    final amount = _amount(text);
    if (amount == null || amount.value <= 0) {
      return ParsedMessage(status: ParseStatus.unparsed, operator: operator, type: type, reason: 'no amount');
    }

    final balance = _first(_balance, text);
    final fee = _first(_fee, text);
    final comm = _first(_comm, text);
    final trx = _trx.firstMatch(text)?.group(1)?.toUpperCase();
    final phone = _counterparty(text);
    final when = _when(text) ?? receivedAt;

    var confidence = 0.5;
    if (trx != null) confidence += 0.25;
    if (balance != null) confidence += 0.15;
    if (senderOp != null) confidence += 0.10;
    if (phone != null) confidence += 0.05;
    if (confidence > 1) confidence = 1;

    var status = ParseStatus.parsed;
    String? reason;
    // Fake-message defence: operator-looking text from a personal number, or
    // sender says one operator while the body names another.
    if (senderOp == null && OperatorDetector.isPersonalNumber(sender)) {
      status = ParseStatus.suspicious;
      reason = 'operator-style message from a personal number';
    } else if (senderOp != null && bodyOp != null && senderOp != bodyOp) {
      status = ParseStatus.suspicious;
      reason = 'sender ${senderOp.name} but body mentions ${bodyOp.name}';
    }

    return ParsedMessage(
      status: status,
      operator: operator,
      type: type,
      amount: amount,
      fee: fee,
      commission: comm,
      balanceAfter: balance,
      counterparty: phone,
      trxId: trx,
      occurredAt: when,
      confidence: confidence,
      reason: reason,
    );
  }

  TxType? _detectType(String text) {
    final t = text.toLowerCase();
    final incoming = RegExp(r'\b(received|receive|from)\b').hasMatch(t);
    if (t.contains('cash in') || t.contains('cash-in') || t.contains('cashin')) return TxType.cashIn;
    if (t.contains('cash out') || t.contains('cash-out') || t.contains('cashout')) return TxType.cashOut;
    if (t.contains('b2b') || t.contains('e-money') || t.contains('emoney') || t.contains('lifting') || t.contains('float')) {
      return incoming ? TxType.b2bIn : TxType.b2bOut;
    }
    if (t.contains('send money') || t.contains('sent money') || t.contains('transfer money') || t.contains('money sent')) {
      return TxType.sendMoney;
    }
    if (t.contains('bill') || t.contains('pay bill') || t.contains('paybill')) return TxType.billPay;
    if (t.contains('recharge') || t.contains('top up') || t.contains('top-up') || t.contains('airtime')) return TxType.recharge;
    if (t.contains('payment')) return incoming ? TxType.payment : TxType.sendMoney;
    if (t.contains('received') || t.contains('money receive') || t.contains('add money')) return TxType.receiveMoney;
    return null;
  }

  Paisa? _amount(String text) {
    // Prefer the first money amount that is not the balance / fee / commission.
    final blocked = <int>{};
    for (final r in [_balance, _fee, _comm]) {
      for (final m in r.allMatches(text)) {
        blocked.add(m.start);
      }
    }
    for (final m in _money.allMatches(text)) {
      final insideBlocked = blocked.any((s) => m.start >= s && m.start <= s + 40);
      if (insideBlocked) continue;
      final p = Paisa.tryParse(m.group(1)!);
      if (p != null) return p;
    }
    // Rocket-style "Tk500.00" already covered; last resort: first number after the type word.
    final m = RegExp(r'(?:in|out|money|payment|b2b|recharge|bill)\s+(?:of\s+)?(?:tk\.?|৳)?\s*([\d,০-৯]+(?:\.\d{1,2})?)', caseSensitive: false).firstMatch(text);
    return m == null ? null : Paisa.tryParse(m.group(1)!);
  }

  Paisa? _first(RegExp r, String text) {
    final m = r.firstMatch(text);
    return m == null ? null : Paisa.tryParse(m.group(1)!);
  }

  String? _counterparty(String text) {
    for (final m in _phone.allMatches(text)) {
      final n = m.group(1)!;
      // Skip if this number is actually part of a TrxID token (rare).
      if (n.length == 11 || n.length == 12 || n.length == 13) return n;
    }
    return null;
  }

  DateTime? _when(String text) {
    final m = _dateTime.firstMatch(text);
    if (m == null) return null;
    var d = int.parse(m.group(1)!);
    var mo = int.parse(m.group(2)!);
    var y = int.parse(m.group(3)!);
    if (y < 100) y += 2000;
    var h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.tryParse(m.group(6) ?? '') ?? 0;
    final ap = m.group(7)?.toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (mo > 12 && d <= 12) {
      final t = d;
      d = mo;
      mo = t;
    }
    try {
      return DateTime(y, mo, d, h, mi, s);
    } catch (_) {
      return null;
    }
  }
}
