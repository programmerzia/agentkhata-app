import 'package:agentkhata/core/core.dart' as core;
import 'package:agentkhata/data/database.dart';
import 'package:agentkhata/data/ingestion_service.dart';
import 'package:agentkhata/data/repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// One phone's side of a shop with several phones.
///
/// The server decides identity — which wallet is which, which of two copies of
/// a transaction is the real one. These tests pin what this phone does with
/// those answers, because each one used to be a way the phone's books drifted
/// from the shop's or its sync stopped for good.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late IngestionService ingest;
  late String cashId;
  late String bkashId;
  late String nagadId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    ingest = IngestionService(repo);
    cashId = await repo.ensureCashWallet();
    bkashId = await repo.upsertWallet(kind: core.WalletKind.bkash, label: 'bKash', openingBalance: core.Paisa.fromTaka(20000));
    nagadId = await repo.upsertWallet(kind: core.WalletKind.nagad, label: 'Nagad', openingBalance: core.Paisa.fromTaka(10000));
    await repo.seedDefaultRulesIfEmpty();
  });

  tearDown(() => db.close());

  const bkashCashIn =
      'Cash In Tk 1,000.00 to 01712345678 successful. Fee Tk 0.00. Balance Tk 19,000.00. TrxID 9AB1CDEF23 at 19/09/2026 10:15';

  Future<List<core.Transaction>> all() => repo.watchAllPosted().first;

  test('a phone that never joined a shop records every operator it has', () async {
    final result = await ingest.ingest(body: bkashCashIn, sender: 'bKash', source: core.TxSource.autoSms);
    expect(result.status, core.ParseStatus.parsed);
  });

  test('a phone that captures only Nagad leaves bKash to the phone that does', () async {
    await repo.setCaptures([nagadId]);
    final result = await ingest.ingest(body: bkashCashIn, sender: 'bKash', source: core.TxSource.autoSms);

    expect(result.status, core.ParseStatus.ignored);
    expect(result.reason, contains('another phone'));
    expect(await all(), isEmpty);
    // Not in Unsorted either: nothing for this phone's owner to do about it.
    expect(await repo.watchUnsorted().first, isEmpty);
  });

  test('a pulled transaction replaces this phone’s own copy of it instead of breaking the pull', () async {
    final mine = await ingest.ingest(body: bkashCashIn, sender: 'bKash', source: core.TxSource.autoSms);
    final localId = mine.transaction!.id;

    // The Upay phone's copy of the same operator transaction reached the
    // server first, under its own id.
    const serverId = '11111111-2222-3333-4444-555555555555';
    await repo.applyRemoteTransaction(
      TransactionsCompanion(
        id: const Value(serverId),
        walletId: Value(bkashId),
        type: const Value(core.TxType.cashIn),
        amount: const Value(100000),
        commission: const Value(410),
        trxId: const Value('9AB1CDEF23'),
        occurredAt: Value(DateTime(2026, 9, 19, 10, 15)),
        source: const Value(core.TxSource.autoNotification),
        status: const Value(core.TxStatus.posted),
        version: const Value(1),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(false),
      ),
      id: serverId,
      walletId: bkashId,
      trxId: '9AB1CDEF23',
      remoteVersion: 1,
    );

    final rows = await all();
    expect(rows.map((t) => t.id), [serverId]);
    // The raw message now points at the row the shop kept.
    final raw = await db.select(db.rawMessages).get();
    expect(raw.single.parsedTransactionId, serverId);
    expect(rows.any((t) => t.id == localId), isFalse);
  });

  test('a merged transaction takes the shop’s id, and waits for the shop’s copy', () async {
    final mine = await ingest.ingest(body: bkashCashIn, sender: 'bKash', source: core.TxSource.autoSms);
    const canonical = '99999999-8888-7777-6666-555555555555';
    await repo.rekeyTransaction(from: mine.transaction!.id, to: canonical);

    final row = await (db.select(db.transactions)..where((t) => t.id.equals(canonical))).getSingle();
    expect(row.dirty, isFalse);
    expect(row.version, 0, reason: 'version 0 lets the shop’s copy overwrite it on the next pull');
  });

  test('adopting the shop’s drawer moves everything posted to this phone’s own', () async {
    await repo.insertTransaction(core.Transaction(
      id: newId(),
      walletId: cashId,
      type: core.TxType.expense,
      amount: core.Paisa.fromTaka(50),
      occurredAt: DateTime.now(),
      source: core.TxSource.manual,
    ));

    const shopDrawer = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    await repo.adoptWallet(
      localId: cashId,
      server: WalletsCompanion(
        id: const Value(shopDrawer),
        kind: const Value(core.WalletKind.cash),
        label: const Value('Cash'),
        openingBalance: const Value(1500000),
        openingAt: Value(DateTime(2026, 9, 1)),
        version: const Value(3),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final wallets = await db.select(db.wallets).get();
    expect(wallets.where((w) => w.kind == core.WalletKind.cash).map((w) => w.id), [shopDrawer]);
    final drawer = wallets.firstWhere((w) => w.id == shopDrawer);
    // The shop's opening stands: one drawer, one opening.
    expect(drawer.openingBalance, 1500000);
    expect(drawer.version, 3);

    final expense = (await all()).single;
    expect(expense.walletId, shopDrawer);
    expect(await repo.unadoptedWallets(), hasLength(2), reason: 'bKash and Nagad still await adoption');
  });
}
