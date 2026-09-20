import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/core.dart';

/// Saying an amount instead of typing it.
///
/// ## Where this actually helps
///
/// Not at the counter — capture is automatic there. It helps for the entries
/// nobody enjoys typing: the tea money, the rickshaw fare, the small cash
/// expenses that go unrecorded precisely because typing them costs more
/// attention than they are worth. An agent who can say "eকশ পঞ্চাশ টাকা চা"
/// while doing something else records an expense they would otherwise skip,
/// and a month of skipped expenses is a profit figure that is simply wrong.
///
/// ## Why it fills the field rather than saving the entry
///
/// Speech recognition is wrong often enough that a voice command which SAVED
/// something would be a voice command that quietly books wrong money. This
/// listens, extracts a number, and puts it in the amount box for the agent to
/// confirm. The worst outcome is a number they have to correct.
///
/// ## Bangla
///
/// Recognition quality depends on what the device has installed, so `bn_BD` is
/// requested and English is the fallback rather than a failure. Bangla numerals
/// in the transcript are converted, because a device that returns "১৫০" and an
/// app that only understands "150" is an app that heard correctly and then
/// threw the answer away.
class VoiceAmount {
  VoiceAmount._(this._speech);

  final SpeechToText _speech;
  static VoiceAmount? _instance;

  static Future<VoiceAmount?> create() async {
    if (_instance != null) return _instance;
    final speech = SpeechToText();
    final ok = await speech.initialize(onError: (_) {}, onStatus: (_) {});
    if (!ok) return null;
    _instance = VoiceAmount._(speech);
    return _instance;
  }

  bool get isListening => _speech.isListening;

  Future<void> stop() => _speech.stop();

  /// Listen, and report each transcript as it firms up.
  Future<void> listen({
    required void Function(String transcript, Paisa? amount, bool isFinal) onResult,
  }) async {
    final locales = await _speech.locales();
    final bangla = locales.where((l) => l.localeId.startsWith('bn')).toList();

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        localeId: bangla.isNotEmpty ? bangla.first.localeId : null,
      ),
      onResult: (result) {
        final words = result.recognizedWords;
        onResult(words, extractAmount(words), result.finalResult);
      },
    );
  }

  /// The first money-shaped number in what was heard.
  ///
  /// Deliberately crude. A cleverer parser that understood "সাড়ে তিনশ" would
  /// be a second thing to keep in step with the message parser for a gain the
  /// agent can achieve by saying the digits. Digits are what people say when
  /// they know a machine is listening.
  static Paisa? extractAmount(String transcript) {
    final latin = transcript.replaceAllMapped(
      RegExp('[০-৯]'),
      (m) => (m[0]!.codeUnitAt(0) - 0x09E6).toString(),
    );
    final match = RegExp(r'(\d[\d,]*(?:\.\d{1,2})?)').firstMatch(latin);
    if (match == null) return null;
    final parsed = Paisa.tryParse(match.group(1)!);
    /*
     * Zero is refused rather than returned. Nobody hands a customer zero taka,
     * so a zero here came from a misheard word, and a zero sitting in the amount
     * field looks like a number somebody entered on purpose.
     */
    if (parsed == null || parsed.value <= 0) return null;
    return parsed;
  }
}

/// The microphone button beside an amount field.
class VoiceAmountButton extends StatefulWidget {
  const VoiceAmountButton({super.key, required this.onAmount, required this.tooltip});

  /// Called with each recognised amount, including partial ones, so the field
  /// updates while the person is still speaking.
  final void Function(Paisa amount) onAmount;
  final String tooltip;

  @override
  State<VoiceAmountButton> createState() => _VoiceAmountButtonState();
}

class _VoiceAmountButtonState extends State<VoiceAmountButton> {
  VoiceAmount? _voice;
  bool _listening = false;
  bool _unavailable = false;

  @override
  Widget build(BuildContext context) {
    if (_unavailable) return const SizedBox.shrink();

    return IconButton(
      tooltip: widget.tooltip,
      isSelected: _listening,
      icon: Icon(_listening ? Icons.mic : Icons.mic_none),
      onPressed: () async {
        _voice ??= await VoiceAmount.create();
        if (_voice == null) {
          setState(() => _unavailable = true);
          return;
        }
        if (_listening) {
          await _voice!.stop();
          if (mounted) setState(() => _listening = false);
          return;
        }
        setState(() => _listening = true);
        await _voice!.listen(
          onResult: (_, amount, isFinal) {
            if (amount != null && amount.value > 0) widget.onAmount(amount);
            if (isFinal && mounted) setState(() => _listening = false);
          },
        );
      },
    );
  }
}
