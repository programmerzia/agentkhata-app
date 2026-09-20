import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Tiny bilingual string table. Bangla is the default; English is a toggle.
class S {
  const S(this.code);
  final String code;

  static S of(WidgetRef ref) => S(ref.watch(localeProvider));

  String call(String key) => (_t[key]?[code == 'bn' ? 0 : 1]) ?? key;

  static const Map<String, List<String>> _t = {
    'app': ['এজেন্ট খাতা', 'AgentKhata'],
    'home': ['হোম', 'Home'],
    'transactions': ['লেনদেন', 'Transactions'],
    'dayclose': ['দিন শেষ', 'Day Close'],
    'customers': ['বাকি', 'Baki'],
    'reports': ['রিপোর্ট', 'Reports'],
    'settings': ['সেটিংস', 'Settings'],
    'total_float': ['মোট ই-মানি', 'Total e-money'],
    'cash_in_hand': ['হাতে নগদ', 'Cash in hand'],
    'today_commission': ['আজকের কমিশন', "Today's commission"],
    'today_tx': ['আজকের লেনদেন', "Today's transactions"],
    'unsorted': ['অমীমাংসিত মেসেজ', 'Unsorted messages'],
    'review': ['যাচাই করুন', 'Review'],
    'add': ['লেনদেন যোগ', 'Add transaction'],
    'amount': ['টাকার পরিমাণ', 'Amount'],
    'type': ['ধরন', 'Type'],
    'wallet': ['ওয়ালেট', 'Wallet'],
    'note': ['নোট', 'Note'],
    'save': ['সংরক্ষণ', 'Save'],
    'cancel': ['বাতিল', 'Cancel'],
    'customer': ['গ্রাহক', 'Customer'],
    'phone': ['ফোন', 'Phone'],
    'name': ['নাম', 'Name'],
    'due': ['পাওনা', 'Due'],
    'remind': ['মনে করিয়ে দিন', 'Remind'],
    'expected': ['হিসাব অনুযায়ী', 'Expected'],
    'actual': ['আসল ব্যালেন্স', 'Actual'],
    'difference': ['পার্থক্য', 'Difference'],
    'close_day': ['দিন শেষ করুন', 'Close the day'],
    'closed': ['দিন শেষ হয়েছে', 'Day closed'],
    'commission': ['কমিশন', 'Commission'],
    'fees': ['ফি', 'Fees'],
    'expenses': ['খরচ', 'Expenses'],
    'drawings': ['মালিকের উত্তোলন', 'Owner drawings'],
    'net_profit': ['নিট লাভ', 'Net profit'],
    'today': ['আজ', 'Today'],
    'this_month': ['এই মাস', 'This month'],
    'last_month': ['গত মাস', 'Last month'],
    'wallets': ['ওয়ালেটসমূহ', 'Wallets'],
    'rates': ['কমিশন রেট', 'Commission rates'],
    'permissions': ['অনুমতি', 'Permissions'],
    'backup': ['ব্যাকআপ', 'Backup'],
    'language': ['ভাষা', 'Language'],
    'notif_access': ['নোটিফিকেশন অ্যাক্সেস', 'Notification access'],
    'notif_access_desc': [
      'বিকাশ/নগদ/রকেট অ্যাপের নোটিফিকেশন পড়ে লেনদেন নিজে থেকে লিখে রাখবে। OTP বা PIN কখনো পড়া হয় না।',
      'Reads bKash/Nagad/Rocket app notifications and records transactions automatically. OTP and PIN are never read.'
    ],
    'sms_access': ['SMS অ্যাক্সেস (ঐচ্ছিক)', 'SMS access (optional)'],
    'granted': ['চালু আছে', 'Enabled'],
    'not_granted': ['চালু নেই', 'Not enabled'],
    'enable': ['চালু করুন', 'Enable'],
    'export': ['ব্যাকআপ শেয়ার করুন', 'Share backup file'],
    'welcome': ['স্বাগতম!', 'Welcome!'],
    'welcome_sub': ['হিসাব লিখতে হবে না, হিসাব নিজেই হবে।', 'You do not write the accounts. They write themselves.'],
    'pick_wallets': ['আপনি কোন কোন সার্ভিস দেন?', 'Which services do you offer?'],
    'opening_balance': ['বর্তমান ব্যালেন্স', 'Current balance'],
    'continue': ['পরবর্তী', 'Continue'],
    'finish': ['শুরু করুন', 'Get started'],
    'runway': ['চলবে আরও', 'Runs out in'],
    'hours': ['ঘণ্টা', 'h'],
    'low_float': ['ব্যালেন্স কম!', 'Low float!'],
    'no_tx': ['এখনো কোনো লেনদেন নেই', 'No transactions yet'],
    'suspicious': ['সন্দেহজনক', 'Suspicious'],
    'accept': ['গ্রহণ', 'Accept'],
    'ignore': ['বাদ দিন', 'Ignore'],
    'void': ['বাতিল করুন', 'Void'],
    'pending': ['যাচাই বাকি', 'Needs review'],
    'give_baki': ['বাকি দিন', 'Give credit'],
    'receive_baki': ['বাকি আদায়', 'Receive payment'],
    'statement_msg': ['আসসালামু আলাইকুম {name}, আপনার বাকি {amt}। দয়া করে পরিশোধ করুন। ধন্যবাদ।', 'Dear {name}, your due is {amt}. Please pay at your earliest. Thank you.'],
    'add_customer': ['নতুন গ্রাহক', 'New customer'],
    'add_wallet': ['ওয়ালেট যোগ', 'Add wallet'],
    'per_thousand': ['প্রতি হাজারে ৳', '৳ per 1,000'],
    'percent': ['শতকরা %', 'Percent %'],
    'flat': ['নির্দিষ্ট ৳', 'Flat ৳'],
    'search': ['খুঁজুন (TrxID / নম্বর)', 'Search (TrxID / number)'],
    'all': ['সব', 'All'],
    'in': ['ইন', 'In'],
    'out': ['আউট', 'Out'],
    'net': ['নিট', 'Net'],
    'by_wallet': ['ওয়ালেট অনুযায়ী কমিশন', 'Commission by wallet'],
    'by_type': ['ধরন অনুযায়ী পরিমাণ', 'Volume by type'],
    'count': ['লেনদেন সংখ্যা', 'Transactions'],
    'connect': ['যুক্ত করুন', 'Connect'],
    'connect_why': [
      'কোরবাড়ির সাথে যুক্ত করলে ওয়েব পোর্টাল, দ্বিতীয় ফোন আর ব্যাকআপ পাবেন। না করলেও অ্যাপ পুরোপুরি চলবে।',
      'Connect to CoreBari for the web portal, a second phone and backup. The app works fully without it.'
    ],
    'connect_failed': ['যুক্ত করা যায়নি। আবার চেষ্টা করুন।', 'Could not connect. Try again.'],
    'disconnect': ['সংযোগ বিচ্ছিন্ন', 'Disconnect'],
    'disconnect_note': [
      'হিসাব ফোনেই থেকে যাবে, শুধু পাঠানো বন্ধ হবে।',
      'The books stay on this phone; only sending stops.'
    ],
    'cloud_sync': ['ক্লাউড সিংক', 'Cloud sync'],
    'cloud_not_configured': ['সার্ভার সেট করা নেই', 'Server not configured'],
    'syncing': ['পাঠানো হচ্ছে…', 'Syncing…'],
    'synced': ['সিংক হয়েছে', 'Synced'],
    'sync_error': ['সিংক ব্যর্থ', 'Sync failed'],
    'sync_read_only': [
      'সাবস্ক্রিপশন বাকি — হিসাব নিরাপদ, বিল দিলে আবার পাঠানো শুরু হবে।',
      'Subscription lapsed. Your books are safe; sending resumes when it is paid.'
    ],
    'sync_unpaired': [
      'এই ফোনের সংযোগ কাটা হয়েছে। আবার যুক্ত করুন।',
      'This phone was disconnected. Connect it again.'
    ],
    'idle': ['অপেক্ষমাণ', 'Idle'],
    'loading': ['লোড হচ্ছে…', 'Loading…'],
    'lock_title': ['অ্যাপ লক', 'App lock'],
    'lock_desc': [
      'ফোন রেখে গেলে অ্যাপ বন্ধ হয়ে যাবে। খুলতে আঙুলের ছাপ বা ফোনের পিন লাগবে।',
      'Closes the app when you put the phone down. Your fingerprint or phone PIN opens it.'
    ],
    'lock_prompt': [
      'হিসাব দেখতে আঙুলের ছাপ বা পিন দিন।',
      'Use your fingerprint or PIN to open your books.'
    ],
    'lock_unlock': ['খুলুন', 'Unlock'],
    'lock_unavailable': [
      'এই ফোনে আঙুলের ছাপ বা স্ক্রিন লক সেট করা নেই।',
      'This phone has no fingerprint or screen lock set up.'
    ],
    'voice_amount': ['বলে টাকার পরিমাণ দিন', 'Say the amount'],
    'topup_request': ['ডিস্ট্রিবিউটরকে লিফটিং চান', 'Ask your distributor for float'],
    'topup_message': [
      'আসসালামু আলাইকুম। {wallet} ওয়ালেটে {amount} লিফটিং দরকার। ধন্যবাদ।',
      'Hello. I need {amount} of float lifted into my {wallet} wallet. Thank you.'
    ],
    'topup_number': ['ডিস্ট্রিবিউটরের নম্বর', "Distributor's number"],
    'topup_saved': ['নম্বর সংরক্ষিত', 'Number saved'],
    'help': ['সাহায্য', 'Help'],
    'help_desc': [
      'সাধারণ প্রশ্নের উত্তর, ইন্টারনেট ছাড়াই।',
      'Answers to the common questions, no network needed.'
    ],
    'widget_add': ['হোম স্ক্রিনে উইজেট যোগ করুন', 'Add the home screen widget'],
    'widget_desc': [
      'ফোন খুলেই ফ্লোট, নগদ আর আজকের হিসাব দেখুন।',
      'See float, cash and today at a glance without opening the app.'
    ],
  };
}

extension SX on WidgetRef {
  S get s => S.of(this);
}

String bnDigits(String s, String code) {
  if (code != 'bn') return s;
  const d = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  return s.replaceAllMapped(RegExp(r'\d'), (m) => d[int.parse(m[0]!)]);
}

class Fmt {
  static String money(BuildContext _, String code, num paisaValue) => moneyOf(code, paisaValue);

  /// The same formatting, for callers with no element in the tree — the home
  /// screen widget bridge formats numbers outside any build.
  static String moneyOf(String code, num paisaValue) => bnDigits(_fmt(paisaValue.toInt()), code);
  static String _fmt(int v) {
    // Delegates to Paisa.format via a light wrapper to keep imports simple.
    final neg = v < 0;
    final abs = v.abs();
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
    return '${neg ? '-' : ''}৳$grouped${frac != 0 ? '.${frac.toString().padLeft(2, '0')}' : ''}';
  }
}
