import 'dart:convert';
import 'dart:io';

import 'package:agentkhata/core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The posting rules, against the same file the server tests load.
///
/// `ledger_cases.json` is a COPY. The canonical file lives in
/// `corebari-apps/apps/agentkhata/src/server/ledger.fixtures.json`, because
/// that is where the database and the portal read it, and a Dart test cannot
/// reach across repositories.
///
/// A copy that nobody notices going stale is worse than no copy at all, so the
/// recorded hash below is checked first. When it fails, run
/// `scripts/sync-fixtures.sh` and then make this implementation agree with the
/// new rules — in that order. Editing the copy alone would make both suites
/// green while the two products disagreed about which way a cash-in moves a
/// wallet, which is exactly the failure this whole arrangement exists to stop.
void main() {
  final file = File('test/fixtures/ledger_cases.json');
  final recordedHash = File('test/fixtures/FIXTURES_SHA').readAsStringSync().trim();

  test('the fixture copy matches its recorded hash', () {
    final actual = sha256.convert(file.readAsBytesSync()).toString();
    expect(
      actual,
      recordedHash,
      reason: 'Fixtures changed without the hash being updated. '
          'Run scripts/sync-fixtures.sh, then make the Dart rules agree.',
    );
  });

  final fixtures = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  final wallets = [
    for (final w in fixtures['wallets'] as List)
      Wallet(
        id: (w as Map)['id'] as String,
        kind: _kindOf(w['kind'] as String),
        label: w['id'] as String,
        openingBalance: Paisa(int.parse(w['openingPoisha'] as String)),
        openingAt: DateTime(2026),
      ),
  ];

  group('ledger fixtures', () {
    for (final raw in fixtures['cases'] as List) {
      final testCase = raw as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final entries = [
          for (final e in testCase['entries'] as List) _entryFrom(e as Map<String, dynamic>),
        ];

        const ledger = Ledger(cashWalletId: 'cash');
        final balances = ledger.balances(wallets, entries);

        (testCase['expectedBalances'] as Map<String, dynamic>).forEach((walletId, expected) {
          expect(
            balances[walletId]?.value.toString(),
            expected,
            reason: 'wallet $walletId',
          );
        });

        final summary = const Reports().summarize(
          entries,
          from: DateTime(2026),
          to: DateTime(2027),
        );
        expect(
          summary.commission.value.toString(),
          testCase['expectedCommissionPoisha'],
        );
        expect(
          summary.netProfit.value.toString(),
          testCase['expectedNetProfitPoisha'],
        );

        final expectedDue = testCase['expectedReceivables'] as Map<String, dynamic>?;
        if (expectedDue != null) {
          final due = const Reports().receivables(entries);
          expectedDue.forEach((partyId, expected) {
            expect(due[partyId]?.value.toString(), expected, reason: 'party $partyId');
          });
        }
      });
    }
  });

  group('commission fixtures', () {
    for (final raw in fixtures['commissionCases'] as List) {
      final testCase = raw as Map<String, dynamic>;
      test(testCase['name'] as String, () {
        final rule = CommissionRule(
          walletKind: WalletKind.bkash,
          txType: TxType.cashIn,
          mode: _modeOf(testCase['mode'] as String),
          ratePpm: testCase['ratePpm'] as int,
        );
        expect(
          rule.compute(Paisa(int.parse(testCase['amountPoisha'] as String))).value.toString(),
          testCase['expectedPoisha'],
        );
      });
    }
  });
}

Transaction _entryFrom(Map<String, dynamic> e) => Transaction(
      id: e['id'] as String,
      walletId: e['walletId'] as String,
      type: _typeOf(e['type'] as String),
      amount: Paisa(int.parse(e['amountPoisha'] as String)),
      commission: Paisa(int.parse(e['commissionPoisha'] as String)),
      fee: Paisa(int.parse(e['feePoisha'] as String)),
      counterWalletId: e['counterWalletId'] as String?,
      customerId: e['partyId'] as String?,
      commissionInCash: e['commissionInCash'] == true,
      occurredAt: DateTime(2026, 6, 15, 10),
    );

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

WalletKind _kindOf(String name) => WalletKind.values.firstWhere((k) => k.name == name);
TxType _typeOf(String name) => TxType.values.firstWhere((t) => _snake(t.name) == name);
RateMode _modeOf(String name) => RateMode.values.firstWhere((m) => _snake(m.name) == name);
