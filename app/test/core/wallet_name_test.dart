import 'package:agentkhata/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Wallet w(String label, [String? n]) => Wallet(id: 'x', kind: WalletKind.bkash, label: label, accountNumber: n, openingAt: DateTime(2026));

  test('two stock-named bKash accounts read differently', () {
    expect(w('bKash', '01711-223344').nameIn('en'), 'bKash ··3344');
    expect(w('bKash', '01811000011').nameIn('en'), 'bKash ··0011');
  });

  test('a chosen name is kept', () => expect(w('Counter 2 bKash', '01711223344').nameIn('bn'), 'Counter 2 bKash'));

  test('no number, just the operator in the language', () => expect(w('bKash').nameIn('bn'), WalletKind.bkash.labelBn));
}
