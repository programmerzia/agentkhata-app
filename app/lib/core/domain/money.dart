/// Money is stored as integer paisa to avoid floating point drift.
/// 1 Taka = 100 paisa.
extension type const Paisa(int value) implements int {
  static const zero = Paisa(0);

  static Paisa fromTaka(num taka) => Paisa((taka * 100).round());

  /// Parses "1,234.56", "1234", "Tk 1,234.50", "৳1,234.5".
  static Paisa? tryParse(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^\d.\-০-৯]'), '')
        .replaceAllMapped(RegExp('[০-৯]'), (m) => (m[0]!.codeUnitAt(0) - 0x09E6).toString());
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '-') return null;
    final d = double.tryParse(cleaned);
    if (d == null) return null;
    return Paisa((d * 100).round());
  }

  double get taka => value / 100;

  Paisa operator +(Paisa o) => Paisa(value + o.value);
  Paisa operator -(Paisa o) => Paisa(value - o.value);
  Paisa operator -() => Paisa(-value);
  bool get isNegative => value < 0;

  /// Formats with Bangladeshi grouping: 12,34,567.89
  String format({bool symbol = true, bool decimals = true}) {
    final neg = value < 0;
    final abs = value.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final s = whole.toString();
    String grouped;
    if (s.length <= 3) {
      grouped = s;
    } else {
      final last3 = s.substring(s.length - 3);
      var rest = s.substring(0, s.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(',')},$last3';
    }
    final buf = StringBuffer();
    if (neg) buf.write('-');
    if (symbol) buf.write('৳');
    buf.write(grouped);
    if (decimals && frac != 0) buf.write('.${frac.toString().padLeft(2, '0')}');
    return buf.toString();
  }
}
