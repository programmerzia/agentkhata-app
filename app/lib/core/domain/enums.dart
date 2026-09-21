/// Wallet kinds the app understands. `cash` is physical cash in the drawer.
enum WalletKind { bkash, nagad, rocket, upay, tap, bank, cash, recharge, other }

extension WalletKindX on WalletKind {
  String get label => switch (this) {
        WalletKind.bkash => 'bKash',
        WalletKind.nagad => 'Nagad',
        WalletKind.rocket => 'Rocket',
        WalletKind.upay => 'Upay',
        WalletKind.tap => 'Tap',
        WalletKind.bank => 'Bank',
        WalletKind.cash => 'Cash',
        WalletKind.recharge => 'Recharge',
        WalletKind.other => 'Other',
      };

  String get labelBn => switch (this) {
        WalletKind.bkash => 'বিকাশ',
        WalletKind.nagad => 'নগদ',
        WalletKind.rocket => 'রকেট',
        WalletKind.upay => 'উপায়',
        WalletKind.tap => 'ট্যাপ',
        WalletKind.bank => 'ব্যাংক',
        WalletKind.cash => 'নগদ টাকা',
        WalletKind.recharge => 'রিচার্জ',
        WalletKind.other => 'অন্যান্য',
      };

  bool get isMfs => const {
        WalletKind.bkash,
        WalletKind.nagad,
        WalletKind.rocket,
        WalletKind.upay,
        WalletKind.tap,
      }.contains(this);
}

/// Every kind of event the ledger can record.
enum TxType {
  cashIn, // customer gives cash, agent sends e-money to customer wallet
  cashOut, // customer withdraws cash from their wallet via agent
  sendMoney, // agent sends e-money (non-customer, e.g. to own number)
  receiveMoney, // agent receives e-money
  b2bIn, // distributor / DSO tops up agent wallet (usually paid in cash)
  b2bOut, // agent returns e-money to distributor
  payment, // merchant payment / bill received into wallet
  recharge, // mobile recharge sold from recharge float
  billPay, // utility bill paid for customer
  expense, // shop expense paid in cash
  drawing, // owner takes cash out
  capital, // owner puts money in
  cashMove, // move between wallet and cash/bank (e.g. bank deposit)
  bakiGiven, // credit given to customer
  bakiReceived, // credit repaid by customer
  adjustment, // manual correction at day close
}

extension TxTypeX on TxType {
  String get label => switch (this) {
        TxType.cashIn => 'Cash In',
        TxType.cashOut => 'Cash Out',
        TxType.sendMoney => 'Send Money',
        TxType.receiveMoney => 'Receive Money',
        TxType.b2bIn => 'B2B In',
        TxType.b2bOut => 'B2B Out',
        TxType.payment => 'Payment',
        TxType.recharge => 'Recharge',
        TxType.billPay => 'Bill Pay',
        TxType.expense => 'Expense',
        TxType.drawing => 'Drawing',
        TxType.capital => 'Capital',
        TxType.cashMove => 'Cash Move',
        TxType.bakiGiven => 'Baki Given',
        TxType.bakiReceived => 'Baki Received',
        TxType.adjustment => 'Adjustment',
      };

  String get labelBn => switch (this) {
        TxType.cashIn => 'ক্যাশ ইন',
        TxType.cashOut => 'ক্যাশ আউট',
        TxType.sendMoney => 'সেন্ড মানি',
        TxType.receiveMoney => 'টাকা গ্রহণ',
        TxType.b2bIn => 'B2B ইন',
        TxType.b2bOut => 'B2B আউট',
        TxType.payment => 'পেমেন্ট',
        TxType.recharge => 'রিচার্জ',
        TxType.billPay => 'বিল পে',
        TxType.expense => 'খরচ',
        TxType.drawing => 'মালিকের উত্তোলন',
        TxType.capital => 'মূলধন',
        TxType.cashMove => 'টাকা স্থানান্তর',
        TxType.bakiGiven => 'বাকি দেওয়া',
        TxType.bakiReceived => 'বাকি আদায়',
        TxType.adjustment => 'সমন্বয়',
      };

  /// True when the entry's own wallet goes DOWN for this type.
  ///
  /// Must agree with `Ledger.postingsFor` — it decides the sign every list
  /// shows and the direction the float advisor counts. It once listed only the
  /// operator-side outflows, so an expense, a drawing or baki given showed as
  /// green money IN and made every runway look longer than it was. A test
  /// (`debitsWallet agrees with the posting rules`) now holds it to the ledger.
  bool get debitsWallet => const {
        TxType.cashIn,
        TxType.sendMoney,
        TxType.billPay,
        TxType.b2bOut,
        TxType.recharge,
        TxType.expense,
        TxType.drawing,
        TxType.cashMove,
        TxType.bakiGiven,
      }.contains(this);

  bool get isAutoCapturable => const {
        TxType.cashIn,
        TxType.cashOut,
        TxType.sendMoney,
        TxType.receiveMoney,
        TxType.b2bIn,
        TxType.b2bOut,
        TxType.payment,
        TxType.billPay,
      }.contains(this);
}

enum TxSource { autoSms, autoNotification, manual, import }

enum TxStatus { posted, pendingReview, voided }

enum ParseStatus { parsed, unparsed, ignored, suspicious, duplicate }
