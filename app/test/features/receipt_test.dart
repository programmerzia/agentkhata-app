import 'package:agentkhata/features/receipts/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a customer number shows only its last three digits', () {
    expect(maskNumber('01711-223344'), '••••••••344');
    expect(maskNumber('123'), '123');
  });

  test('numbers become the 880 form WhatsApp wants', () {
    expect(intlBd('01711223344'), '8801711223344');
    expect(intlBd('+880 1711-223344'), '8801711223344');
    expect(intlBd(''), isNull);
    expect(intlBd(null), isNull);
  });
}
