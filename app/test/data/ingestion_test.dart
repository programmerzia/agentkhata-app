import 'package:agentkhata/core/core.dart' as core;
import 'package:agentkhata/data/database.dart';
import 'package:agentkhata/data/ingestion_service.dart';
import 'package:agentkhata/data/repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end: raw operator text → transaction in the database, with
/// dedup, commission, review routing, secret filtering and float math.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late IngestionService svc;
  late String bkashId;
  late String cashId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    svc = IngestionService(repo);
    cashId = await repo.ensureCashWallet();
    await repo.upsertWallet(id: cashId, kind: core.WalletKind.cash, label: 'Cash', openingBalance: core.Paisa.fromTaka(5000));
    bkashId = await repo.upsertWallet(kind: core.WalletKind.bkash, label: 'bKash', openingBalance: core.Paisa.fromTaka(20000));
    await repo.upsertWallet(kind: core.WalletKind.nagad, label: 'Nagad', openingBalance: core.Paisa.fromTaka(10000));
    await repo.seedDefaultRulesIfEmpty();
  });

  tearDown(() => db.close());

  Future<Map<String, core.Paisa>> balances() async =>
      core.Ledger(cashWalletId: cashId).balances(await repo.wallets(), (await repo.watchAllPosted().first).where((t) => t.status == core.TxStatus.posted));

  test('SMS cash-in is posted with rule commission and moves balances', () async {
    final r = await svc.ingest(
      body: 'Cash In Tk 1,000.00 to 01712345678 successful. Fee Tk 0.00. Balance Tk 19,000.00. TrxID 9AB1CDEF23 at 19/09/2026 10:15',
      sender: 'bKash',
      source: core.TxSource.autoSms,
    );
    expect(r.status, core.ParseStatus.parsed);
    expect(r.transaction!.status, core.TxStatus.posted);
    expect(r.transaction!.commission, core.Paisa(410));
    final b = await balances();
    expect(b[bkashId], core.Paisa.fromTaka(20000 - 1000 + 4.10));
    expect(b[cashId], core.Paisa.fromTaka(6000));
  });

  test('operator-stated commission wins over the rule', () async {
    final r = await svc.ingest(
      body: 'Cash Out Tk 2,000.00 from 01812345678 successful. Comm Tk 7.50. Balance Tk 22,007.50. TrxID 9AB1CDEF99 at 19/09/2026 10:20',
      sender: 'bKash',
      source: core.TxSource.autoSms,
    );
    expect(r.transaction!.commission, core.Paisa(750));
  });

  test('same event from SMS and notification is stored once', () async {
    const sms = 'Cash In Tk 500.00 to 01712345678 successful. Balance Tk 19,500.00. TrxID DUP1234567 at 19/09/2026 10:15';
    final a = await svc.ingest(body: sms, sender: 'bKash', source: core.TxSource.autoSms);
    final b = await svc.ingest(body: sms, sender: 'com.bkash.businessapp', packageName: 'com.bkash.businessapp', source: core.TxSource.autoNotification);
    expect(a.status, core.ParseStatus.parsed);
    expect(b.status, core.ParseStatus.duplicate);
    final all = await repo.watchAllPosted().first;
    expect(all.length, 1);
  });

  test('low-confidence message goes to review, not to the books', () async {
    final r = await svc.ingest(body: 'Cash In Tk 300.00 successful.', sender: 'com.bkash.businessapp', packageName: 'com.bkash.businessapp', source: core.TxSource.autoNotification);
    expect(r.status, core.ParseStatus.parsed);
    expect(r.transaction!.status, core.TxStatus.pendingReview);
    final b = await balances();
    expect(b[bkashId], core.Paisa.fromTaka(20000));
  });

  test('OTP never touches storage; unrelated SMS is ignored', () async {
    final a = await svc.ingest(body: 'Your bKash OTP is 445566. Do not share.', sender: 'bKash', source: core.TxSource.autoSms);
    final b = await svc.ingest(body: 'Eid Mubarak from your bank', sender: 'BANK', source: core.TxSource.autoSms);
    expect(a.status, core.ParseStatus.ignored);
    expect(b.status, core.ParseStatus.ignored);
    expect(await db.rawMessages.count().getSingle(), 0);
  });

  test('operator wallet not configured lands in unsorted with a reason', () async {
    final r = await svc.ingest(body: 'Cash In Tk500.00 to A/C 017123456789 successful. Bal Tk8,500.00. TxnId 1234567890', sender: '16216', source: core.TxSource.autoSms);
    expect(r.status, core.ParseStatus.unparsed);
    expect(r.reason, contains('Rocket'));
    final unsorted = await repo.watchUnsorted().first;
    expect(unsorted.length, 1);
  });

  test('suspicious message from a personal number is quarantined', () async {
    final r = await svc.ingest(
      body: 'Cash In Tk 9,000.00 to 01712345678 successful. Balance Tk 1.00. TrxID FAKE000001 bKash',
      sender: '01799999999',
      source: core.TxSource.autoSms,
    );
    expect(r.status, core.ParseStatus.suspicious);
    expect((await repo.watchAllPosted().first), isEmpty);
  });

  test('backup round-trips', () async {
    await svc.ingest(body: 'Cash In Tk 1,000.00 to 01712345678 successful. Balance Tk 19,000.00. TrxID RT00000001 at 19/09/2026 10:15', sender: 'bKash', source: core.TxSource.autoSms);
    final json = await repo.exportJson();
    final db2 = AppDatabase(NativeDatabase.memory());
    final repo2 = Repository(db2);
    await repo2.importJson(json);
    expect((await repo2.wallets()).length, 3);
    expect((await repo2.watchAllPosted().first).length, 1);
    await db2.close();
  });

  test('a NESCO bill keeps its meter number all the way into the books', () async {
    final r = await svc.ingest(
      body: 'Bill successfully paid.\nBiller: NESCOPre \nMMYYYY/Contact: 01718424859\nA/C: 78032986 \nAmount: Tk 500.00 \nFee: Tk 5.00 \nTrxID: DHK4MGM1W6 at 20/08/2026 11:20',
      sender: '16247',
      source: core.TxSource.autoSms,
    );

    expect(r.status, core.ParseStatus.parsed);
    final saved = (await repo.watchAllPosted().first).firstWhere((t) => t.trxId == 'DHK4MGM1W6');
    expect(saved.type, core.TxType.billPay);
    expect(saved.billerName, 'NESCOPre');
    // The number the customer reads out when the power is still off.
    expect(saved.billerAccount, '78032986');
    expect(saved.amount, core.Paisa.fromTaka(500));
  });

  test('a recharge sold through bKash reaches the books once, not twice', () async {
    final first = await svc.ingest(
      body: 'Received Recharge request of Tk 22.00 for 01581344833. Fee Tk 0.00. Balance Tk 9,028.17. TrxID DIM6RM4AB2 at 22/09/2026 20:37. Wait for confirmation.',
      sender: '16247',
      source: core.TxSource.autoSms,
    );
    final second = await svc.ingest(
      body: 'Your bKash Mobile Recharge request of Tk 22.00 for 01581344833 was successful! Use bKash App for convenience & offers! TCA',
      sender: '16247',
      source: core.TxSource.autoSms,
    );

    expect(first.status, core.ParseStatus.parsed);
    expect(second.status, core.ParseStatus.ignored);
    final recharges = (await repo.watchAllPosted().first).where((t) => t.type == core.TxType.recharge).toList();
    expect(recharges.length, 1);
    expect(recharges.single.counterparty, '01581344833');
  });

}
