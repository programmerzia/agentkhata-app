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
}
