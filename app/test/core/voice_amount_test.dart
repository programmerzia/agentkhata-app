import 'package:agentkhata/core/core.dart';
import 'package:agentkhata/features/voice/voice_amount.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the recogniser hands back is a sentence, not a number.
///
/// Bangla speech recognition returns Bangla numerals, sometimes with the word
/// for taka attached and sometimes with the amount in the middle of a phrase.
/// Every case below is one that a real utterance produces.
void main() {
  test('reads an amount out of Bangla speech', () {
    expect(VoiceAmount.extractAmount('পাঁচ হাজার ৫০০০'), Paisa.fromTaka(5000));
    expect(VoiceAmount.extractAmount('৳ ১২৫০'), Paisa.fromTaka(1250));
    expect(VoiceAmount.extractAmount('২৩০০ টাকা'), Paisa.fromTaka(2300));
  });

  test('reads an amount out of English speech', () {
    expect(VoiceAmount.extractAmount('1500'), Paisa.fromTaka(1500));
    expect(VoiceAmount.extractAmount('send 2,400 taka'), Paisa.fromTaka(2400));
    expect(VoiceAmount.extractAmount('750.50'), Paisa.fromTaka(750.5));
  });

  test('refuses what is not an amount rather than guessing one', () {
    expect(VoiceAmount.extractAmount(''), isNull);
    expect(VoiceAmount.extractAmount('bkash'), isNull);
    // Nobody hands a customer zero taka, and a zero in the field looks saved.
    expect(VoiceAmount.extractAmount('০'), isNull);
  });
}
