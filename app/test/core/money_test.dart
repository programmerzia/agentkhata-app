import 'package:agentkhata/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Bangladeshi grouping', () {
    expect(Paisa(123456789).format(), '৳12,34,567.89');
    expect(Paisa(100000).format(), '৳1,000');
    expect(Paisa(99900).format(), '৳999');
    expect(Paisa(-250).format(), '-৳2.50');
    expect(Paisa(1000000000).format(symbol: false), '1,00,00,000');
  });
  test('parse', () {
    expect(Paisa.tryParse('Tk 1,234.5'), Paisa(123450));
    expect(Paisa.tryParse('৳500'), Paisa(50000));
    expect(Paisa.tryParse('abc'), isNull);
    expect(Paisa.fromTaka(4.10), Paisa(410));
  });
}
