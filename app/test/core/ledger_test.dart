import 'package:agentkhata/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 9, 19, 8);
  final wallets = [
    Wallet(id: 'cash', kind: WalletKind.cash, label: 'Cash', openingBalance: Paisa.fromTaka(10000), openingAt: t0),
    Wallet(id: 'bk', kind: WalletKind.bkash, label: 'bKash', openingBalance: Paisa.fromTaka(50000), openingAt: t0),
  ];
  const ledger = Ledger(cashWalletId: 'cash');

  Transaction tx(String id, TxType type, num taka, {Paisa comm = Paisa.zero, Paisa fee = Paisa.zero, int minute = 0, String? cust, String? counter}) =>
      Transaction(id: id, walletId: 'bk', type: type, amount: Paisa.fromTaka(taka), commission: comm, fee: fee, occurredAt: t0.add(Duration(minutes: minute)), customerId: cust, counterWalletId: counter);

  test('cash in moves e-money out and cash in, commission credited', () {
    final b = ledger.balances(wallets, [tx('1', TxType.cashIn, 1000, comm: Paisa(410))]);
    expect(b['bk'], Paisa.fromTaka(50000 - 1000 + 4.10));
    expect(b['cash'], Paisa.fromTaka(11000));
  });

  test('cash out is the mirror', () {
    final b = ledger.balances(wallets, [tx('1', TxType.cashOut, 500, comm: Paisa(205))]);
    expect(b['bk'], Paisa.fromTaka(50000 + 500 + 2.05));
    expect(b['cash'], Paisa.fromTaka(9500));
  });

  test('b2b in pays cash to distributor', () {
    final b = ledger.balances(wallets, [tx('1', TxType.b2bIn, 20000)]);
    expect(b['bk'], Paisa.fromTaka(70000));
    expect(b['cash'], Paisa.fromTaka(-10000));
  });

  test('expense and drawing from cash', () {
    final exp = Transaction(id: 'e', walletId: 'cash', type: TxType.expense, amount: Paisa.fromTaka(200), occurredAt: t0, note: 'tea');
    final dr = Transaction(id: 'd', walletId: 'cash', type: TxType.drawing, amount: Paisa.fromTaka(1000), occurredAt: t0);
    final b = ledger.balances(wallets, [exp, dr]);
    expect(b['cash'], Paisa.fromTaka(8800));
    expect(b['bk'], Paisa.fromTaka(50000));
  });

  test('voided transactions are ignored, until filter works', () {
    final a = tx('1', TxType.cashIn, 1000, minute: 10);
    final v = tx('2', TxType.cashIn, 1000, minute: 20).copyWith(status: TxStatus.voided);
    final late = tx('3', TxType.cashIn, 1000, minute: 120);
    final b = ledger.balances(wallets, [a, v, late], until: t0.add(const Duration(hours: 1)));
    expect(b['bk'], Paisa.fromTaka(49000));
  });

  test('postings always balance', () {
    for (final type in TxType.values) {
      final p = ledger.postingsFor(tx('x', type, 123.45, comm: Paisa(50), fee: Paisa(10), cust: 'c1'));
      expect(p.fold<int>(0, (s, x) => s + x.delta.value), 0, reason: type.name);
    }
  });

  test('reports and receivables', () {
    final txs = [
      tx('1', TxType.cashIn, 1000, comm: Paisa(410), minute: 1),
      tx('2', TxType.cashOut, 2000, comm: Paisa(820), fee: Paisa(100), minute: 2),
      Transaction(id: 'e', walletId: 'cash', type: TxType.expense, amount: Paisa.fromTaka(300), occurredAt: t0.add(const Duration(minutes: 3))),
      Transaction(id: 'b1', walletId: 'cash', type: TxType.bakiGiven, amount: Paisa.fromTaka(500), occurredAt: t0, customerId: 'rahim'),
      Transaction(id: 'b2', walletId: 'cash', type: TxType.bakiReceived, amount: Paisa.fromTaka(200), occurredAt: t0, customerId: 'rahim'),
    ];
    final s = const Reports().summarize(txs, from: t0, to: t0.add(const Duration(days: 1)));
    expect(s.commission, Paisa(1230));
    expect(s.fees, Paisa(100));
    expect(s.expenses, Paisa.fromTaka(300));
    expect(s.netProfit, Paisa(1230 - 100 - 30000));
    expect(s.count, 5);
    expect(const Reports().receivables(txs)['rahim'], Paisa.fromTaka(300));
  });

  test('commission engine prefers operator value, else rule', () {
    final e = CommissionEngine();
    expect(e.commissionFor(kind: WalletKind.bkash, type: TxType.cashIn, amount: Paisa.fromTaka(1000)), Paisa(410));
    expect(e.commissionFor(kind: WalletKind.bkash, type: TxType.cashIn, amount: Paisa.fromTaka(1000), statedByOperator: Paisa(399)), Paisa(399));
    expect(e.commissionFor(kind: WalletKind.bkash, type: TxType.sendMoney, amount: Paisa.fromTaka(1000)), Paisa.zero);
    expect(e.commissionFor(kind: WalletKind.recharge, type: TxType.recharge, amount: Paisa.fromTaka(100)), Paisa(275));
  });

  test('deduplicator matches by trxId and by fuzzy fields', () {
    const d = Deduplicator();
    final existing = Transaction(id: '1', walletId: 'bk', type: TxType.cashIn, amount: Paisa(100000), trxId: 'ABC', occurredAt: t0, balanceAfter: Paisa(500));
    final byTrx = ParsedMessage(status: ParseStatus.parsed, type: TxType.cashIn, amount: Paisa(100000), trxId: 'ABC', occurredAt: t0.add(const Duration(hours: 5)));
    expect(d.findDuplicate(byTrx, [existing], receivedAt: t0), existing);
    final fuzzy = ParsedMessage(status: ParseStatus.parsed, type: TxType.cashIn, amount: Paisa(100000), occurredAt: t0.add(const Duration(minutes: 1)), balanceAfter: Paisa(500));
    expect(d.findDuplicate(fuzzy, [existing], receivedAt: t0), existing);
    final different = ParsedMessage(status: ParseStatus.parsed, type: TxType.cashIn, amount: Paisa(100000), occurredAt: t0.add(const Duration(minutes: 1)), balanceAfter: Paisa(900));
    expect(d.findDuplicate(different, [existing], receivedAt: t0), isNull);
  });

  test('float advisor flags draining wallet', () {
    final now = t0.add(const Duration(days: 7));
    final txs = [for (var i = 0; i < 7; i++) tx('$i', TxType.cashIn, 6000, minute: i * 1440)];
    final a = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(1000), txs: txs, now: now);
    expect(a.burnPerHour, Paisa.fromTaka(500));
    expect(a.hoursLeft, closeTo(2, 0.01));
    expect(a.level, FloatLevel.low);
    final ok = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(100000), txs: txs, now: now);
    expect(ok.level, FloatLevel.ok);

    // An overdrawn wallet has no runway, and must not report a negative one:
    // that reads as meaningless and sorts as the least urgent row on the board.
    final empty = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(-500), txs: txs, now: now);
    expect(empty.level, FloatLevel.critical);
    expect(empty.hoursLeft, 0);
  });

  test('suggested lifting covers a trading day, rounded the way it is asked for', () {
    final now = t0.add(const Duration(days: 7));
    final txs = [for (var i = 0; i < 7; i++) tx('$i', TxType.cashIn, 6000, minute: i * 1440)];

    // Burning 500/hour with 1,000 left: twelve hours needs 6,000, so 5,000 more,
    // and nobody asks a distributor for 5,000 exactly by accident.
    final low = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(1000), txs: txs, now: now);
    expect(low.suggestedLift(), Paisa.fromTaka(5000));

    // Already holding more than a day of cover: asking for nothing is the
    // correct answer, and the button hides on it.
    final flush = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(100000), txs: txs, now: now);
    expect(flush.suggestedLift(), Paisa.zero);

    // A wallet nobody is spending from cannot be given a sensible number.
    final idle = const FloatAdvisor().advise(wallet: wallets[1], balance: Paisa.fromTaka(1000), txs: const [], now: now);
    expect(idle.suggestedLift(), Paisa.zero);
  });

  test('debitsWallet agrees with the posting rules for every type', () {
    for (final type in TxType.values) {
      final t = tx('sign-${type.name}', type, 100, cust: 'c1', counter: 'cash');
      final own = ledger
          .postingsFor(t)
          .where((p) => p.account.walletId == t.walletId)
          .fold<int>(0, (sum, p) => sum + p.delta.value);
      expect(own < 0, type.debitsWallet, reason: '${type.name}: ledger moves the wallet by $own');
    }
  });

  group('service charges differ by operator and by biller', () {
    const bkashDefault = CommissionRule(walletKind: WalletKind.bkash, txType: TxType.billPay, mode: RateMode.flat, flatPoisha: 500, takenInCash: true);
    const rocketCheaper = CommissionRule(walletKind: WalletKind.rocket, txType: TxType.billPay, mode: RateMode.flat, flatPoisha: 300, takenInCash: true);
    const wasaDearer = CommissionRule(walletKind: WalletKind.bkash, txType: TxType.billPay, mode: RateMode.flat, flatPoisha: 1000, takenInCash: true, billerMatch: 'WASA');
    final engine = CommissionEngine(const [bkashDefault, rocketCheaper, wasaDearer]);

    Paisa charge(WalletKind kind, {String? biller}) =>
        engine.commissionFor(kind: kind, type: TxType.billPay, amount: Paisa.fromTaka(500), biller: biller);

    test('each operator keeps its own rate', () {
      expect(charge(WalletKind.bkash), Paisa.fromTaka(5));
      expect(charge(WalletKind.rocket), Paisa.fromTaka(3));
    });

    test('a rule naming a biller beats the shop\'s ordinary rate', () {
      expect(charge(WalletKind.bkash, biller: 'WASA'), Paisa.fromTaka(10));
      expect(charge(WalletKind.bkash, biller: 'NESCOPre'), Paisa.fromTaka(5));
    });

    test('a biller rule never leaks onto another operator', () {
      expect(charge(WalletKind.rocket, biller: 'WASA'), Paisa.fromTaka(3));
    });

    test('NESCOPre matches a rule written for NESCO', () {
      final e = CommissionEngine(const [
        bkashDefault,
        CommissionRule(walletKind: WalletKind.bkash, txType: TxType.billPay, mode: RateMode.flat, flatPoisha: 800, takenInCash: true, billerMatch: 'NESCO'),
      ]);
      expect(
        e.commissionFor(kind: WalletKind.bkash, type: TxType.billPay, amount: Paisa.fromTaka(500), biller: 'NESCOPre'),
        Paisa.fromTaka(8),
      );
    });
  });
}
