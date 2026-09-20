import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/core.dart' as core;
import 'database.dart';
import 'mappers.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Single entry point for all reads and writes. Keeps the UI free of SQL and
/// keeps the domain layer free of Drift.
class Repository {
  Repository(this.db);
  final AppDatabase db;

  // ---------- wallets ----------
  Stream<List<core.Wallet>> watchWallets({bool activeOnly = true}) {
    final q = db.select(db.wallets)..orderBy([(w) => OrderingTerm.asc(w.sortOrder), (w) => OrderingTerm.asc(w.label)]);
    q.where((w) => w.deletedAt.isNull());
    if (activeOnly) q.where((w) => w.isActive.equals(true));
    return q.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  Future<List<core.Wallet>> wallets({bool activeOnly = true}) => watchWallets(activeOnly: activeOnly).first;

  Future<core.Wallet?> walletOfKind(core.WalletKind kind) async {
    final row = await (db.select(db.wallets)..where((w) => w.kind.equalsValue(kind) & w.isActive.equals(true) & w.deletedAt.isNull())..limit(1)).getSingleOrNull();
    return row?.toDomain();
  }

  Future<String> ensureCashWallet() async {
    final existing = await walletOfKind(core.WalletKind.cash);
    if (existing != null) return existing.id;
    final id = newId();
    await db.into(db.wallets).insert(WalletsCompanion.insert(
          id: id,
          kind: core.WalletKind.cash,
          label: 'Cash',
          openingAt: DateTime.now(),
          sortOrder: const Value(-1),
          updatedAt: Value(DateTime.now()),
          dirty: const Value(true),
        ));
    return id;
  }

  Future<String> upsertWallet({
    String? id,
    required core.WalletKind kind,
    required String label,
    String? accountNumber,
    core.Paisa openingBalance = core.Paisa.zero,
    DateTime? openingAt,
    bool isActive = true,
  }) async {
    final wid = id ?? newId();
    await db.into(db.wallets).insertOnConflictUpdate(WalletsCompanion(
          id: Value(wid),
          kind: Value(kind),
          label: Value(label),
          accountNumber: Value(accountNumber),
          openingBalance: Value(openingBalance.value),
          openingAt: Value(openingAt ?? DateTime.now()),
          isActive: Value(isActive),
          updatedAt: Value(DateTime.now()),
          dirty: const Value(true),
        ));
    return wid;
  }

  Future<void> setWalletActive(String id, bool active) =>
      (db.update(db.wallets)..where((w) => w.id.equals(id))).write(WalletsCompanion(isActive: Value(active), updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  // ---------- transactions ----------
  Stream<List<core.Transaction>> watchTransactions({DateTime? from, DateTime? to, String? walletId, int? limit}) {
    final q = db.select(db.transactions)..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    q.where((t) {
      Expression<bool> e = (t.status.equalsValue(core.TxStatus.posted) | t.status.equalsValue(core.TxStatus.pendingReview)) & t.deletedAt.isNull();
      if (from != null) e = e & t.occurredAt.isBiggerOrEqualValue(from);
      if (to != null) e = e & t.occurredAt.isSmallerThanValue(to);
      if (walletId != null) e = e & t.walletId.equals(walletId);
      return e;
    });
    if (limit != null) q.limit(limit);
    return q.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  Stream<List<core.Transaction>> watchAllPosted() => watchTransactions();

  /// Candidates for duplicate detection: exact TrxID matches (any age) plus
  /// everything that happened around [near].
  Future<List<core.Transaction>> dedupCandidates({String? trxId, required DateTime near, Duration window = const Duration(minutes: 10)}) async {
    final rows = await (db.select(db.transactions)
          ..where((t) {
            Expression<bool> e = t.occurredAt.isBetweenValues(near.subtract(window), near.add(window));
            if (trxId != null) e = e | t.trxId.equals(trxId);
            return e;
          }))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  Future<void> insertTransaction(core.Transaction t) => db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: t.id,
        walletId: t.walletId,
        type: t.type,
        amount: t.amount.value,
        fee: Value(t.fee.value),
        commission: Value(t.commission.value),
        counterparty: Value(t.counterparty),
        trxId: Value(t.trxId),
        balanceAfter: Value(t.balanceAfter?.value),
        occurredAt: t.occurredAt,
        source: t.source,
        rawMessageId: Value(t.rawMessageId),
        note: Value(t.note),
        customerId: Value(t.customerId),
        counterWalletId: Value(t.counterWalletId),
        status: Value(t.status),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ));

  Future<void> setStatus(String id, core.TxStatus status) =>
      (db.update(db.transactions)..where((t) => t.id.equals(id))).write(TransactionsCompanion(status: Value(status), updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> updateTransaction(core.Transaction t) => (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(TransactionsCompanion(
        walletId: Value(t.walletId),
        type: Value(t.type),
        amount: Value(t.amount.value),
        fee: Value(t.fee.value),
        commission: Value(t.commission.value),
        counterparty: Value(t.counterparty),
        note: Value(t.note),
        customerId: Value(t.customerId),
        counterWalletId: Value(t.counterWalletId),
        occurredAt: Value(t.occurredAt),
        status: Value(t.status),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ));

  // ---------- raw messages ----------
  Future<void> insertRaw(core.RawMessage m, {String? reason}) => db.into(db.rawMessages).insert(RawMessagesCompanion.insert(
        id: m.id,
        source: m.source,
        sender: m.sender,
        packageName: Value(m.packageName),
        body: m.body,
        receivedAt: m.receivedAt,
        parseStatus: m.parseStatus,
        parsedTransactionId: Value(m.parsedTransactionId),
        reason: Value(reason),
      ));

  Stream<List<RawMessageRow>> watchUnsorted() => (db.select(db.rawMessages)
        ..where((r) => r.parseStatus.equalsValue(core.ParseStatus.unparsed) | r.parseStatus.equalsValue(core.ParseStatus.suspicious))
        ..orderBy([(r) => OrderingTerm.desc(r.receivedAt)]))
      .watch();

  Future<void> markRaw(String id, core.ParseStatus status, {String? txId}) =>
      (db.update(db.rawMessages)..where((r) => r.id.equals(id))).write(RawMessagesCompanion(parseStatus: Value(status), parsedTransactionId: Value(txId)));

  // ---------- customers ----------
  Stream<List<core.Customer>> watchCustomers() =>
      (db.select(db.customers)..where((c) => c.deletedAt.isNull())..orderBy([(c) => OrderingTerm.asc(c.name)])).watch().map((r) => r.map((c) => c.toDomain()).toList());

  Future<String> upsertCustomer({String? id, required String name, String? phone, String? note}) async {
    final cid = id ?? newId();
    await db.into(db.customers).insertOnConflictUpdate(CustomersCompanion(id: Value(cid), name: Value(name), phone: Value(phone), note: Value(note), updatedAt: Value(DateTime.now()), dirty: const Value(true)));
    return cid;
  }

  // ---------- day close ----------
  Stream<List<core.DayClose>> watchDayCloses({int limit = 60}) => (db.select(db.dayCloses)
        ..where((d) => d.deletedAt.isNull())
        ..orderBy([(d) => OrderingTerm.desc(d.date)])
        ..limit(limit))
      .watch()
      .map((r) => r.map((d) => d.toDomain()).toList());

  Future<List<core.DayClose>> dayClosesOn(DateTime day) async {
    final d0 = DateTime(day.year, day.month, day.day);
    final rows = await (db.select(db.dayCloses)..where((d) => d.date.equals(d0))).get();
    return rows.map((r) => r.toDomain()).toList();
  }

  Future<void> saveDayClose(core.DayClose c) => db.into(db.dayCloses).insertOnConflictUpdate(DayClosesCompanion(
        id: Value(c.id),
        date: Value(DateTime(c.date.year, c.date.month, c.date.day)),
        walletId: Value(c.walletId),
        expected: Value(c.expected.value),
        actual: Value(c.actual.value),
        note: Value(c.note),
        closedAt: Value(c.closedAt),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ));

  // ---------- commission rules ----------
  Future<List<core.CommissionRule>> commissionRules() async {
    final rows = await (db.select(db.commissionRules)..where((r) => r.deletedAt.isNull())).get();
    if (rows.isEmpty) return core.CommissionEngine.defaultRules;
    return rows.map((r) => r.toDomain()).toList();
  }

  Stream<List<CommissionRuleRow>> watchCommissionRuleRows() => (db.select(db.commissionRules)..where((r) => r.deletedAt.isNull())).watch();

  Future<void> seedDefaultRulesIfEmpty() async {
    final count = await db.commissionRules.count().getSingle();
    if (count > 0) return;
    await db.batch((b) {
      for (final r in core.CommissionEngine.defaultRules) {
        b.insert(
          db.commissionRules,
          CommissionRulesCompanion.insert(
            id: newId(),
            walletKind: r.walletKind,
            txType: r.txType,
            mode: r.mode,
            ratePpm: Value(r.ratePpm),
            flatPoisha: Value(r.flatPoisha),
            updatedAt: Value(DateTime.now()),
            dirty: const Value(true),
          ),
        );
      }
    });
  }

  Future<void> upsertRule({
    String? id,
    required core.WalletKind kind,
    required core.TxType type,
    required core.RateMode mode,
    required int ratePpm,
    int? flatPoisha,
  }) =>
      db.into(db.commissionRules).insertOnConflictUpdate(
            CommissionRulesCompanion(
              id: Value(id ?? newId()),
              walletKind: Value(kind),
              txType: Value(type),
              mode: Value(mode),
              ratePpm: Value(ratePpm),
              flatPoisha: Value(flatPoisha),
              updatedAt: Value(DateTime.now()),
              dirty: const Value(true),
            ),
          );

  // ---------- backup ----------
  Future<Map<String, dynamic>> exportJson() async => {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'wallets': (await db.select(db.wallets).get()).map((r) => r.toJson()).toList(),
        'transactions': (await db.select(db.transactions).get()).map((r) => r.toJson()).toList(),
        'customers': (await db.select(db.customers).get()).map((r) => r.toJson()).toList(),
        'dayCloses': (await db.select(db.dayCloses).get()).map((r) => r.toJson()).toList(),
        'commissionRules': (await db.select(db.commissionRules).get()).map((r) => r.toJson()).toList(),
      };

  Future<void> importJson(Map<String, dynamic> j) => db.transaction(() async {
        for (final w in (j['wallets'] as List)) {
          await db.into(db.wallets).insertOnConflictUpdate(WalletRow.fromJson(w as Map<String, dynamic>));
        }
        for (final c in (j['customers'] as List? ?? [])) {
          await db.into(db.customers).insertOnConflictUpdate(CustomerRow.fromJson(c as Map<String, dynamic>));
        }
        for (final t in (j['transactions'] as List)) {
          await db.into(db.transactions).insertOnConflictUpdate(TransactionRow.fromJson(t as Map<String, dynamic>));
        }
        for (final d in (j['dayCloses'] as List? ?? [])) {
          await db.into(db.dayCloses).insertOnConflictUpdate(DayCloseRow.fromJson(d as Map<String, dynamic>));
        }
        for (final r in (j['commissionRules'] as List? ?? [])) {
          await db.into(db.commissionRules).insertOnConflictUpdate(CommissionRuleRow.fromJson(r as Map<String, dynamic>));
        }
      });

  // ---------- sync support ----------
  Future<String?> meta(String key) async => (await (db.select(db.syncMeta)..where((m) => m.key.equals(key))).getSingleOrNull())?.value;
  Future<void> setMeta(String key, String value) => db.into(db.syncMeta).insertOnConflictUpdate(SyncMetaCompanion(key: Value(key), value: Value(value)));

  Future<List<WalletRow>> dirtyWallets() => (db.select(db.wallets)..where((w) => w.dirty.equals(true))).get();
  Future<List<TransactionRow>> dirtyTransactions() => (db.select(db.transactions)..where((t) => t.dirty.equals(true))).get();
  Future<List<CustomerRow>> dirtyCustomers() => (db.select(db.customers)..where((c) => c.dirty.equals(true))).get();
  Future<List<DayCloseRow>> dirtyDayCloses() => (db.select(db.dayCloses)..where((d) => d.dirty.equals(true))).get();
  Future<List<CommissionRuleRow>> dirtyRules() => (db.select(db.commissionRules)..where((r) => r.dirty.equals(true))).get();

  Future<void> markClean(TableInfo table, List<String> ids) async {
    if (ids.isEmpty) return;
    await customUpdate('UPDATE ${table.actualTableName} SET dirty = 0 WHERE id IN (${List.filled(ids.length, '?').join(',')})',
        variables: ids.map(Variable.withString).toList(), updates: {table});
  }

  /// Apply a row the server sent.
  ///
  /// A local row that is still DIRTY is left alone: it holds an edit this
  /// phone has not managed to push yet, and overwriting it here would lose
  /// that edit silently — the exact failure the version scheme exists to
  /// prevent. The next push sends it, and if the server refuses as a conflict
  /// the conflict path decides.
  Future<void> applyRemote(
    TableInfo table,
    Insertable<dynamic> row, {
    required String id,
    required int remoteVersion,
  }) async {
    final existing = await customSelect(
      'SELECT version, dirty FROM ${table.actualTableName} WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();

    if (existing != null) {
      if (existing.read<int>('dirty') == 1) return;
      if (existing.read<int>('version') >= remoteVersion) return;
    }
    await db.into(table).insertOnConflictUpdate(row);
  }

  /// Record the version the server assigned, without clearing `dirty`.
  Future<void> setVersion(TableInfo table, String id, int version) => customUpdate(
        'UPDATE ${table.actualTableName} SET version = ? WHERE id = ?',
        variables: [Variable.withInt(version), Variable.withString(id)],
        updates: {table},
      );

  /// A push the server refused as stale.
  ///
  /// Status-wins: if this row's local change was a void or an accept, it stays
  /// dirty and is re-pushed on the version the server just reported, because a
  /// person decided that about money. Anything else gives way to the server
  /// copy, which the next pull applies now that the row is clean.
  Future<void> resolveConflict(TableInfo table, String id) async {
    if (table.actualTableName != db.transactions.actualTableName) {
      await customUpdate(
        'UPDATE ${table.actualTableName} SET dirty = 0 WHERE id = ?',
        variables: [Variable.withString(id)],
        updates: {table},
      );
      return;
    }
    final row = await customSelect(
      'SELECT status FROM transactions WHERE id = ?',
      variables: [Variable.withString(id)],
    ).getSingleOrNull();
    final status = row?.read<int>('status');
    final decidedByHuman =
        status == core.TxStatus.voided.index || status == core.TxStatus.posted.index;
    if (decidedByHuman) return; // stays dirty, re-pushed on the new version
    await customUpdate(
      'UPDATE transactions SET dirty = 0 WHERE id = ?',
      variables: [Variable.withString(id)],
      updates: {table},
    );
  }

  Future<void> softDelete(TableInfo table, String id) => customUpdate(
        'UPDATE ${table.actualTableName} SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?',
        variables: [Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000), Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000), Variable.withString(id)],
        updates: {table},
      );

  Future<int> customUpdate(String sql, {required List<Variable> variables, required Set<TableInfo> updates}) => db.customUpdate(sql, variables: variables, updates: updates);
  Selectable<QueryRow> customSelect(String sql, {required List<Variable> variables}) => db.customSelect(sql, variables: variables);

  /// Moves everything that referenced wallet [from] onto [to] and removes [from].
  Future<void> replaceWalletId({required String from, required String to, required core.WalletKind kind, required String label, required int openingBalance, required DateTime openingAt}) =>
      db.transaction(() async {
        await db.into(db.wallets).insertOnConflictUpdate(WalletsCompanion(
          id: Value(to), kind: Value(kind), label: Value(label), openingBalance: Value(openingBalance), openingAt: Value(openingAt),
          updatedAt: Value(DateTime.fromMillisecondsSinceEpoch(0)), dirty: const Value(false),
        ));
        await (db.update(db.transactions)..where((t) => t.walletId.equals(from))).write(TransactionsCompanion(walletId: Value(to), updatedAt: Value(DateTime.now()), dirty: const Value(true)));
        await (db.update(db.transactions)..where((t) => t.counterWalletId.equals(from))).write(TransactionsCompanion(counterWalletId: Value(to), updatedAt: Value(DateTime.now()), dirty: const Value(true)));
        await (db.update(db.dayCloses)..where((d) => d.walletId.equals(from))).write(DayClosesCompanion(walletId: Value(to), updatedAt: Value(DateTime.now()), dirty: const Value(true)));
        await (db.delete(db.wallets)..where((w) => w.id.equals(from))).go();
      });
}
