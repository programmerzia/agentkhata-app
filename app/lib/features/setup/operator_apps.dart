import '../../core/core.dart';
import '../../platform/message_channel.dart';

/// Which operators this phone has apps for.
///
/// The basis for every pre-ticked box in setup: an agent whose phone has the
/// bKash Agent app and the Nagad Uddokta app sees bKash and Nagad already
/// chosen, and a phone with only Upay sees only Upay. Asking "which services
/// do you offer?" on a blank list is a question; showing the answer and asking
/// "right?" is a tap.
Future<Set<WalletKind>> operatorsOnThisPhone() async {
  final packages = await MessageChannel.installedOperatorApps();
  return {for (final package in packages) ?_kindOf(package)};
}

WalletKind? _kindOf(String package) => switch (package) {
      'com.bkash.businessapp' || 'com.bkash.customerapp' => WalletKind.bkash,
      'com.konasl.nagad.agent' || 'com.konasl.nagad' => WalletKind.nagad,
      'com.dbbl.mbs.apps.main' => WalletKind.rocket,
      'com.ucb.upay' => WalletKind.upay,
      'com.trustbank.tap' => WalletKind.tap,
      _ => null,
    };
