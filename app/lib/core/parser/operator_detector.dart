import '../domain/enums.dart';

/// Maps SMS sender IDs and Android package names to a wallet kind.
class OperatorDetector {
  static const Map<WalletKind, List<String>> senderIds = {
    WalletKind.bkash: ['bkash', '16247'],
    WalletKind.nagad: ['nagad', '16167'],
    WalletKind.rocket: ['16216', 'rocket', 'dbbl'],
    WalletKind.upay: ['upay', '16268'],
    WalletKind.tap: ['tap', '16733'],
  };

  static const Map<String, WalletKind> packages = {
    'com.bkash.businessapp': WalletKind.bkash,
    'com.bkash.customerapp': WalletKind.bkash,
    'com.konasl.nagad.agent': WalletKind.nagad,
    'com.konasl.nagad': WalletKind.nagad,
    'com.dbbl.mbs.apps.main': WalletKind.rocket,
    'com.ucb.upay': WalletKind.upay,
    'com.trustbank.tap': WalletKind.tap,
  };

  /// Detects operator from sender / package. Returns null when unknown.
  static WalletKind? fromSender(String sender, {String? packageName}) {
    if (packageName != null) {
      final k = packages[packageName];
      if (k != null) return k;
    }
    final s = sender.trim().toLowerCase();
    for (final e in senderIds.entries) {
      if (e.value.any((id) => s == id || s.contains(id))) return e.key;
    }
    return null;
  }

  /// Detects operator from message body wording (used to spot fake senders).
  static WalletKind? fromBody(String body) {
    final b = body.toLowerCase();
    if (b.contains('bkash')) return WalletKind.bkash;
    if (b.contains('nagad')) return WalletKind.nagad;
    if (b.contains('rocket') || b.contains('dbbl')) return WalletKind.rocket;
    if (b.contains('upay')) return WalletKind.upay;
    if (RegExp(r'\btap\b').hasMatch(b)) return WalletKind.tap;
    return null;
  }

  /// True when the sender looks like a personal phone number rather than a
  /// short code or alphanumeric operator ID.
  static bool isPersonalNumber(String sender) =>
      RegExp(r'^(\+?88)?01\d{9}$').hasMatch(sender.replaceAll(RegExp(r'[\s-]'), ''));
}
