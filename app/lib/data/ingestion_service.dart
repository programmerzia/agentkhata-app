import '../core/core.dart' as core;
import 'repository.dart';

/// Result of pushing one message through the pipeline, for logging / UI toasts.
class IngestResult {
  const IngestResult(this.status, {this.transaction, this.reason});
  final core.ParseStatus status;
  final core.Transaction? transaction;
  final String? reason;
}

/// raw text → parse → safety → dedup → commission → persist.
///
/// This is the heart of "zero typing". It is deliberately conservative: anything
/// it is not sure about lands in the Unsorted inbox instead of the books.
class IngestionService {
  IngestionService(this.repo, {core.MessageParser? parser , core.Deduplicator? dedup })
      : _parser = parser ?? const core.MessageParser(),
        _dedup = dedup ?? const core.Deduplicator();

  final Repository repo;
  final core.MessageParser _parser;
  final core.Deduplicator _dedup;

  Future<IngestResult> ingest({
    required String body,
    required String sender,
    String? packageName,
    required core.TxSource source,
    DateTime? receivedAt,
  }) async {
    final at = receivedAt ?? DateTime.now();
    final parsed = _parser.parse(body, sender: sender, packageName: packageName, receivedAt: at);
    final rawId = newId();

    Future<IngestResult> keep(core.ParseStatus st, {String? reason, String? txId}) async {
      await repo.insertRaw(
        core.RawMessage(id: rawId, source: source, sender: sender, packageName: packageName, body: body, receivedAt: at, parseStatus: st, parsedTransactionId: txId),
        reason: reason,
      );
      return IngestResult(st, reason: reason);
    }

    // Do not even store secrets or unrelated messages.
    if (parsed.status == core.ParseStatus.ignored) return IngestResult(parsed.status, reason: parsed.reason);
    if (parsed.status == core.ParseStatus.unparsed) return keep(core.ParseStatus.unparsed, reason: parsed.reason);
    if (parsed.status == core.ParseStatus.suspicious) return keep(core.ParseStatus.suspicious, reason: parsed.reason);

    /*
     * Which wallet this message belongs in — and whether it is THIS phone's
     * to record at all.
     *
     * In a shop with several phones, every phone holds every wallet (the books
     * are shared) but each captures only its own operators: bKash and Nagad
     * here, Upay on the next handset. A bKash notification reaching the Upay
     * phone — the agent's personal bKash, say — must not post into the shop's
     * bKash float. It is ignored here, not stored: the phone that captures
     * bKash records the real ones, and the server merges any it sees twice.
     */
    final match = await repo.walletForCapture(parsed.operator!);
    if (match.wallet == null) {
      return keep(core.ParseStatus.unparsed, reason: 'no ${parsed.operator!.label} wallet configured');
    }
    if (!match.captured) {
      return IngestResult(core.ParseStatus.ignored, reason: '${parsed.operator!.label} is captured by another phone');
    }
    final wallet = match.wallet!;

    final dup = _dedup.findDuplicate(parsed, await repo.dedupCandidates(trxId: parsed.trxId, near: parsed.occurredAt ?? at), receivedAt: at);
    if (dup != null) return keep(core.ParseStatus.duplicate, reason: 'duplicate of ${dup.id}', txId: dup.id);

    final engine = core.CommissionEngine(await repo.commissionRules());
    final commission = engine.commissionFor(kind: wallet.kind, type: parsed.type!, amount: parsed.amount!, statedByOperator: parsed.commission, at: parsed.occurredAt);

    final tx = core.Transaction(
      id: newId(),
      walletId: wallet.id,
      type: parsed.type!,
      amount: parsed.amount!,
      fee: parsed.fee ?? core.Paisa.zero,
      commission: commission,
      counterparty: parsed.counterparty,
      trxId: parsed.trxId,
      balanceAfter: parsed.balanceAfter,
      occurredAt: parsed.occurredAt ?? at,
      source: source,
      rawMessageId: rawId,
      status: parsed.confidence >= core.MessageParser.autoPostThreshold ? core.TxStatus.posted : core.TxStatus.pendingReview,
    );
    try {
      await repo.insertTransaction(tx);
    } catch (e) {
      // Unique (wallet, trxId) index is the last line of defence against double posting.
      return keep(core.ParseStatus.duplicate, reason: 'trxId already recorded');
    }
    await keep(core.ParseStatus.parsed, txId: tx.id);
    return IngestResult(core.ParseStatus.parsed, transaction: tx);
  }

  /// A message the pipeline threw on, kept where a person will see it.
  ///
  /// Stored as Unsorted with the error as the reason, so it can be classified
  /// by hand like any other message the parser could not read — rather than
  /// retried on every start, failing identically, and holding up the queue.
  Future<void> recordFailure({
    required String body,
    required String sender,
    String? packageName,
    required bool isSms,
    required DateTime receivedAt,
    required Object error,
  }) async {
    try {
      await repo.insertRaw(
        core.RawMessage(
          id: newId(),
          source: isSms ? core.TxSource.autoSms : core.TxSource.autoNotification,
          sender: sender,
          packageName: packageName,
          body: body,
          receivedAt: receivedAt,
          parseStatus: core.ParseStatus.unparsed,
        ),
        reason: 'could not be processed: ${error.runtimeType}',
      );
    } catch (_) {
      // The database itself is failing; nothing more useful can be done here,
      // and the message is acknowledged so it does not block every later one.
    }
  }
}
