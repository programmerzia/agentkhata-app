import '../core/core.dart';

/// Enum names on the wire, not indices.
///
/// The server stores these vocabularies as Postgres enums with readable
/// labels — `cash_in`, `auto_sms`, `per_thousand`. This file is the only place
/// that knows the Dart spelling of each, and it maps by NAME in both
/// directions on purpose.
///
/// The alternative, sending `TxType.values.indexOf(...)`, works right up until
/// somebody reorders the Dart enum for readability. At that moment every
/// historical row in Postgres silently changes meaning, and nothing fails —
/// the numbers still parse. A name that does not match throws on the first row
/// instead, in development, which is the failure this file exists to buy.

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

extension WalletKindWire on WalletKind {
  String get wireName => name;
}

extension WalletKindIndex on WalletKind {
  static WalletKind ofName(dynamic value) => WalletKind.values.firstWhere(
        (k) => k.name == value,
        orElse: () => WalletKind.other,
      );
}

extension TxTypeWire on TxType {
  /// `cashIn` becomes `cash_in`, matching `agentkhata.entry_type`.
  String get wireName => _snake(name);
}

extension TxTypeIndex on TxType {
  static TxType ofName(dynamic value) => TxType.values.firstWhere(
        (t) => _snake(t.name) == value,
        orElse: () => TxType.adjustment,
      );
}

extension TxSourceWire on TxSource {
  String get wireName => _snake(name);
}

extension TxSourceIndex on TxSource {
  static TxSource ofName(dynamic value) => TxSource.values.firstWhere(
        (s) => _snake(s.name) == value,
        orElse: () => TxSource.manual,
      );
}

extension TxStatusWire on TxStatus {
  String get wireName => _snake(name);
}

extension TxStatusIndex on TxStatus {
  static TxStatus ofName(dynamic value) => TxStatus.values.firstWhere(
        (s) => _snake(s.name) == value,
        orElse: () => TxStatus.posted,
      );
}

extension RateModeWire on RateMode {
  String get wireName => _snake(name);
}

extension RateModeIndex on RateMode {
  static RateMode ofName(dynamic value) => RateMode.values.firstWhere(
        (m) => _snake(m.name) == value,
        orElse: () => RateMode.perThousand,
      );
}
