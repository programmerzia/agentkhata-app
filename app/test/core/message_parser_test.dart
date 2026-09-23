import 'package:agentkhata/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const p = MessageParser();
  final rx = DateTime(2026, 9, 19, 10, 0);

  group('bKash agent', () {
    test('cash in', () {
      final r = p.parse(
        'Cash In Tk 1,000.00 to 01712345678 successful. Fee Tk 0.00. Balance Tk 25,340.50. TrxID 9AB1CDEF23 at 19/09/2026 10:15',
        sender: 'bKash',
        receivedAt: rx,
      );
      expect(r.status, ParseStatus.parsed);
      expect(r.operator, WalletKind.bkash);
      expect(r.type, TxType.cashIn);
      expect(r.amount, Paisa(100000));
      expect(r.fee, Paisa.zero);
      expect(r.balanceAfter, Paisa(2534050));
      expect(r.trxId, '9AB1CDEF23');
      expect(r.counterparty, '01712345678');
      expect(r.occurredAt, DateTime(2026, 9, 19, 10, 15));
      expect(r.confidence, greaterThanOrEqualTo(MessageParser.autoPostThreshold));
    });

    test('cash out with commission', () {
      final r = p.parse(
        'Cash Out Tk 500.00 from 01812345678 successful. Fee Tk 0.00. Comm Tk 2.05. Balance Tk 25,842.55. TrxID 9AB1CDEF24 at 19/09/2026 10:20',
        sender: 'bKash',
      );
      expect(r.type, TxType.cashOut);
      expect(r.amount, Paisa(50000));
      expect(r.commission, Paisa(205));
      expect(r.balanceAfter, Paisa(2584255));
    });

    test('b2b received', () {
      final r = p.parse(
        'You have received B2B Tk 50,000.00 from 01912345678. Balance Tk 75,842.55. TrxID 9AB1CDEF25 at 19/09/2026 11:00',
        sender: '16247',
      );
      expect(r.operator, WalletKind.bkash);
      expect(r.type, TxType.b2bIn);
      expect(r.amount, Paisa(5000000));
    });

    test('received payment', () {
      final r = p.parse(
        'You have received payment Tk 300.00 from 01612345678. Balance Tk 76,142.55. TrxID 9AB1CDEF26 at 19/09/2026 11:05',
        sender: 'bKash',
      );
      expect(r.type, TxType.payment);
    });

    test('notification from agent app', () {
      final r = p.parse(
        'Cash In Tk 200.00 to 01712345678 successful. Balance Tk 100.00. TrxID ABC123DEF4',
        sender: '',
        packageName: 'com.bkash.businessapp',
        receivedAt: rx,
      );
      expect(r.operator, WalletKind.bkash);
      expect(r.status, ParseStatus.parsed);
      expect(r.occurredAt, rx);
    });
  });

  group('Nagad uddokta', () {
    test('cash in with colon fields', () {
      final r = p.parse(
        'Cash In Tk 2,000.00 to 01512345678 successful. Comm: Tk 8.20. Balance: Tk 12,345.67. TxnID: 74ABCDEF. 19/09/2026 12:15',
        sender: 'NAGAD',
      );
      expect(r.operator, WalletKind.nagad);
      expect(r.type, TxType.cashIn);
      expect(r.amount, Paisa(200000));
      expect(r.commission, Paisa(820));
      expect(r.balanceAfter, Paisa(1234567));
      expect(r.trxId, '74ABCDEF');
    });

    test('money received', () {
      final r = p.parse('Money Received Tk 150.00 from 01312345678. Balance Tk 12,495.67. TxnID 74ABCDEG. 19/09/2026 12:20', sender: '16167');
      expect(r.type, TxType.receiveMoney);
    });
  });

  group('Rocket', () {
    test('compact Tk500.00 style with 12-digit account', () {
      final r = p.parse(
        'Cash In Tk500.00 to A/C 017123456789 successful. Fee Tk0.00. Comm Tk2.08. Bal Tk8,500.00. TxnId 1234567890 at 19-09-2026 13:05:33',
        sender: '16216',
      );
      expect(r.operator, WalletKind.rocket);
      expect(r.type, TxType.cashIn);
      expect(r.amount, Paisa(50000));
      expect(r.commission, Paisa(208));
      expect(r.balanceAfter, Paisa(850000));
      expect(r.counterparty, '017123456789');
      expect(r.trxId, '1234567890');
    });
  });

  group('Upay', () {
    test('cash out', () {
      final r = p.parse(
        'Cash Out of Tk 700.00 from 01412345678 is successful. Fee Tk 0.00. Balance Tk 3,300.00. TrxID UP12345678 at 19/09/2026 02:10 PM',
        sender: 'upay',
      );
      expect(r.operator, WalletKind.upay);
      expect(r.type, TxType.cashOut);
      expect(r.amount, Paisa(70000));
      expect(r.occurredAt, DateTime(2026, 9, 19, 14, 10));
    });
  });

  group('safety', () {
    test('OTP is dropped', () {
      final r = p.parse('Your bKash OTP is 123456. Do not share.', sender: 'bKash');
      expect(r.status, ParseStatus.ignored);
      expect(r.reason, 'secret');
    });
    test('PIN reset is dropped', () {
      final r = p.parse('Your PIN has been reset. Cash In Tk 100.00', sender: 'bKash');
      expect(r.status, ParseStatus.ignored);
    });
    test('failed transaction is ignored', () {
      final r = p.parse('Cash Out Tk 500.00 from 01812345678 failed. Balance Tk 25,842.55.', sender: 'bKash');
      expect(r.status, ParseStatus.ignored);
    });
    test('promo is ignored', () {
      final r = p.parse('Congratulations! Get 10% cashback offer on bKash payment this Eid.', sender: 'bKash');
      expect(r.status, ParseStatus.ignored);
    });
    test('fake operator message from personal number is suspicious', () {
      final r = p.parse(
        'Cash In Tk 5,000.00 to 01712345678 successful. Balance Tk 25,340.50. TrxID FAKE123456 at 19/09/2026 10:15 bKash',
        sender: '01799999999',
      );
      expect(r.status, ParseStatus.suspicious);
      expect(r.isTransaction, isTrue);
    });
    test('unrelated SMS is ignored', () {
      final r = p.parse('Your Grameenphone bill is due.', sender: 'GP');
      expect(r.status, ParseStatus.ignored);
    });
    test('Bangla digits are understood', () {
      final r = p.parse('Cash In Tk ১,০০০.০০ to 01712345678 successful. Balance Tk ৫,০০০.০০. TrxID 9AB1CDEF27', sender: 'bKash');
      expect(r.amount, Paisa(100000));
      expect(r.balanceAfter, Paisa(500000));
    });
  });

  group('what a real phone actually receives', () {
    // Sent in by the shop owner from a live handset, kept word for word:
    // every space, line break and abbreviation is what the operator writes.
    const p = MessageParser();

    test('a NESCO prepaid bill keeps the biller and the meter number', () {
      final r = p.parse(
        'Bill successfully paid.\nBiller: NESCOPre \nMMYYYY/Contact: 01718424859\nA/C: 78032986 \nAmount: Tk 500.00 \nFee: Tk 5.00 \nTrxID: DHK4MGM1W6 at 20/08/2026 11:20',
        sender: '16247',
      );
      expect(r.status, ParseStatus.parsed);
      expect(r.type, TxType.billPay);
      expect(r.amount, Paisa.fromTaka(500));
      expect(r.fee, Paisa.fromTaka(5));
      expect(r.billerName, 'NESCOPre');
      // The one thing a customer comes back with when the power stays off.
      expect(r.billerAccount, '78032986');
      expect(r.trxId, 'DHK4MGM1W6');
      expect(r.occurredAt, DateTime(2026, 8, 20, 11, 20));
    });

    test('a recharge is recorded from the request, which already states the balance', () {
      final r = p.parse(
        'Received Recharge request of Tk 22.00 for 01581344833. Fee Tk 0.00. Balance Tk 9,028.17. TrxID DIM6RM4AB2 at 22/09/2026 20:37. Wait for confirmation.',
        sender: '16247',
      );
      expect(r.status, ParseStatus.parsed, reason: 'the float has already left the wallet');
      expect(r.type, TxType.recharge);
      expect(r.amount, Paisa.fromTaka(22));
      expect(r.balanceAfter, Paisa.fromTaka(9028.17));
      expect(r.counterparty, '01581344833');
      expect(r.trxId, 'DIM6RM4AB2');
    });

    test('the confirmation that follows it is not a second recharge', () {
      final r = p.parse(
        'Your bKash Mobile Recharge request of Tk 22.00 for 01581344833 was successful! Use bKash App for convenience & offers! TCA',
        sender: '16247',
      );
      expect(r.status, ParseStatus.ignored);
    });

    test('a genuinely failed transaction is still ignored', () {
      final r = p.parse(
        'Your Recharge request of Tk 22.00 for 01581344833 was unsuccessful. TrxID DIM6RM4AB3 at 22/09/2026 20:38.',
        sender: '16247',
      );
      expect(r.status, ParseStatus.ignored);
    });
  });
}
