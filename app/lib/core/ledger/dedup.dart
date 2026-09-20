import '../domain/models.dart';
import '../parser/parsed_message.dart';

/// Detects whether an incoming parsed message is already in the ledger.
/// The same event often arrives twice: once as an SMS and once as an app
/// notification, sometimes with a different wording.
class Deduplicator {
  const Deduplicator({this.window = const Duration(minutes: 3)});
  final Duration window;

  Transaction? findDuplicate(ParsedMessage m, Iterable<Transaction> recent, {required DateTime receivedAt}) {
    for (final t in recent) {
      if (m.trxId != null && t.trxId != null && m.trxId == t.trxId) return t;
    }
    final when = m.occurredAt ?? receivedAt;
    for (final t in recent) {
      if (t.type != m.type || t.amount != m.amount) continue;
      final dt = t.occurredAt.difference(when).abs();
      if (dt > window) continue;
      final sameBalance = m.balanceAfter == null || t.balanceAfter == null || m.balanceAfter == t.balanceAfter;
      final sameParty = m.counterparty == null || t.counterparty == null || m.counterparty == t.counterparty;
      if (sameBalance && sameParty) return t;
    }
    return null;
  }
}
