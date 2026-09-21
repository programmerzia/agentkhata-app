import 'package:flutter/material.dart';

import '../core/core.dart';

/// The CoreBari palette, as Dart.
///
/// This file is the ONLY place in the app that may name a colour, mirroring
/// the rule the web suite enforces with a conventions check: hex lives in
/// `packages/ui/src/tokens.ts` there and here, and nowhere else. A screen that
/// needs a colour reads it from this class.
///
/// The values are CoreBari's own, taken from `corebari/brand/COLOURS.md` and
/// the AgentKhata accent added to `APP_ACCENTS` — so an agent who also runs
/// Dokani sees one family of products rather than two unrelated apps.
class AppTheme {
  /// Deep indigo: AgentKhata's accent in the CoreBari suite.
  ///
  /// Chosen because every screen in this app is covered in the OPERATORS'
  /// brand colours — bKash magenta, Nagad orange, Rocket purple — and the app
  /// accent has one job those do not: to stay out of their way. See the note
  /// beside `agentkhata` in the web tokens file for the full reasoning.
  static const seed = Color(0xFF3346A6);

  /// CoreBari navy, brick and blueprint — the suite's own three.
  static const navy = Color(0xFF0B1330);
  static const brick = Color(0xFFA8462A);
  static const blueprint = Color(0xFF8FD3FF);
  static const ivory = Color(0xFFF4F1E9);

  /// The worksheet surfaces the apps use in light mode.
  static const page = Color(0xFFF4F2EC);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1A1830);
  static const inkDim = Color(0xFF5A5678);
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  /// The type stack, matching the web suite.
  ///
  /// IBM Plex Sans for text, Noto Sans Bengali for Bangla, and IBM Plex Mono
  /// for every number. The mono face on money is not decoration: a column of
  /// amounts in a proportional face does not line up, and this app is columns
  /// of amounts read at a glance by someone counting a drawer.
  ///
  /// Named rather than bundled: the families resolve if the device has them
  /// and fall back to the platform's own otherwise, which on a cheap Android
  /// in Bangladesh means a working Bangla face either way. Bundling the files
  /// is a size decision to revisit once the APK is measured on a real phone.
  static const _sans = 'IBM Plex Sans';
  static const _mono = 'IBM Plex Mono';

  /// One radius system, three values — the same contract as the web tokens.
  static const radiusControl = 8.0;
  static const radiusCard = 16.0;

  static ThemeData _base(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: b,
      surface: b == Brightness.light ? page : navy,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _sans,
      fontFamilyFallback: const ['Noto Sans Bengali'],
      visualDensity: VisualDensity.comfortable,
      // A hairline instead of a shadow: on the cheap, bright screens agents
      // use, soft shadows vanish and cards blur into the page.
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
        color: b == Brightness.light ? card : scheme.surfaceContainerLow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: b == Brightness.light ? page : navy,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: _sans, fontSize: 20, fontWeight: FontWeight.w700, color: b == Brightness.light ? ink : ivory),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusControl)),
        isDense: true,
      ),
      listTileTheme: const ListTileThemeData(dense: true),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primary.withValues(alpha: .14),
        backgroundColor: b == Brightness.light ? card : scheme.surfaceContainer,
      ),
      // Money, balances and counts. Tabular so columns align.
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontFamily: _mono, fontFeatures: [FontFeature.tabularFigures()]),
        headlineMedium: TextStyle(fontFamily: _mono, fontFeatures: [FontFeature.tabularFigures()]),
      ).apply(fontFamily: _sans),
    );
  }

  static Color walletColor(WalletKind k) => switch (k) {
        WalletKind.bkash => const Color(0xFFE2136E),
        WalletKind.nagad => const Color(0xFFF6921E),
        WalletKind.rocket => const Color(0xFF8C3494),
        WalletKind.upay => const Color(0xFF1E88E5),
        WalletKind.tap => const Color(0xFF00897B),
        WalletKind.bank => const Color(0xFF455A64),
        WalletKind.cash => const Color(0xFF2E7D32),
        WalletKind.recharge => const Color(0xFF6D4C41),
        WalletKind.other => const Color(0xFF757575),
      };

  static IconData walletIcon(WalletKind k) => switch (k) {
        WalletKind.cash => Icons.payments_outlined,
        WalletKind.bank => Icons.account_balance_outlined,
        WalletKind.recharge => Icons.phone_android_outlined,
        _ => Icons.account_balance_wallet_outlined,
      };

  static IconData txIcon(TxType t) => switch (t) {
        TxType.cashIn => Icons.south_west,
        TxType.cashOut => Icons.north_east,
        TxType.b2bIn => Icons.local_shipping_outlined,
        TxType.b2bOut => Icons.local_shipping_outlined,
        TxType.sendMoney => Icons.send_outlined,
        TxType.receiveMoney || TxType.payment => Icons.call_received,
        TxType.recharge => Icons.phone_android_outlined,
        TxType.billPay => Icons.receipt_long_outlined,
        TxType.expense => Icons.shopping_bag_outlined,
        TxType.drawing => Icons.person_remove_outlined,
        TxType.capital => Icons.person_add_alt_outlined,
        TxType.cashMove => Icons.swap_horiz,
        TxType.bakiGiven => Icons.handshake_outlined,
        TxType.bakiReceived => Icons.handshake,
        TxType.adjustment => Icons.tune,
      };
}
