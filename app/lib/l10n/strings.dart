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
    'history': ['আগের হিসাব', 'History'],
    'why_unknown_type': ['কী ধরনের লেনদেন বোঝা যায়নি', 'Could not tell what kind of transaction this is'],
    'why_no_amount': ['টাকার অঙ্ক পাওয়া যায়নি', 'No amount found in the message'],
    'why_personal_sender': ['অপারেটরের মতো মেসেজ, কিন্তু এসেছে ব্যক্তিগত নম্বর থেকে — প্রতারণা হতে পারে', 'Looks like an operator message but came from a personal number — could be fraud'],
    'why_sender_mismatch': ['পাঠানো নম্বর আর মেসেজের অপারেটর মেলে না', 'The sender and the operator named in the message do not match'],
    'why_no_wallet': ['এই অপারেটরের কোনো অ্যাকাউন্ট যোগ করা নেই', 'No account set up for this operator'],
    'why_duplicate': ['এই লেনদেন আগেই লেখা হয়েছে', 'Already recorded'],
    'why_failed': ['প্রসেস করা যায়নি', 'Could not be processed'],
    'enter_amount': ['সঠিক টাকার অঙ্ক লিখুন', 'Enter a valid amount'],
    'choose_wallet': ['একটি অ্যাকাউন্ট বেছে নিন', 'Choose an account'],
    'choose_customer': ['একজন কাস্টমার বেছে নিন', 'Choose a customer'],
    'undo': ['ফেরত আনুন', 'Undo'],
    'ignored_one': ['মেসেজটি বাদ দেওয়া হলো', 'Message ignored'],
    'receipt': ['রসিদ', 'Receipt'],
    'receipt_no': ['রসিদ নং', 'Receipt no.'],
    'time': ['সময়', 'Time'],
    'balance_after': ['পরে ব্যালান্স', 'Balance after'],
    'account': ['অ্যাকাউন্ট', 'Account'],
    'share_pdf': ['PDF রসিদ পাঠান', 'Share PDF receipt'],
    'share_image': ['ছবি পাঠান', 'Share image'],
    'share_hint': ['হোয়াটসঅ্যাপ, মেসেঞ্জার, ইমো — যেকোনো অ্যাপে পাঠাতে পারবেন', 'Send it on WhatsApp, Messenger, imo — any app'],
    'receipt_thanks': ['ধন্যবাদ। আবার আসবেন।', 'Thank you. Please come again.'],
    'voided_one': ['লেনদেন বাতিল হলো', 'Entry voided'],
    'receipt_header': ['রসিদে দোকানের তথ্য', 'Shop details on receipts'],
    'receipt_header_sub': ['রসিদ আর হিসাব বিবরণীতে যা ছাপা হবে', 'Printed on receipts and statements'],
    'shop_name': ['দোকানের নাম', 'Shop name'],
    'statement': ['হিসাব বিবরণী', 'Statement'],
    'statement_sub': ['PDF বা ছবি করে পাঠান', 'Send as PDF or picture'],
    'share_pdf_statement': ['PDF বিবরণী পাঠান', 'Share PDF statement'],
    'as_of': ['তারিখ:', 'As of'],
    'date': ['তারিখ', 'Date'],
    'baki_given_short': ['বাকি', 'Credit'],
    'paid_short': ['জমা', 'Paid'],
    'balance': ['বাকি থাকল', 'Balance'],
    'brought_forward': ['আগের জের', 'Brought forward'],
    'no_baki_yet': ['এখনো কোনো বাকি নেই', 'No credit yet'],
    'total_due': ['মোট বাকি', 'Total due'],
    'remind_all': ['সবাইকে মনে করান', 'Remind everyone'],
    'remind_all_sub': ['{n} জনের কাছে টাকা পাওনা। প্রতিটি বোতাম মেসেজ লিখে রাখে — আপনি শুধু পাঠান চাপবেন। আজ পাঠানো হয়েছে: {done}', '{n} customers owe you. Each button writes the message; you just press send. Sent today: {done}'],
    'remind_no_phone': ['আরো {n} জনের ফোন নম্বর নেই — নম্বর যোগ করলে এখানে আসবে', '{n} more have no phone number — add one and they appear here'],
    'nobody_owes': ['কারো কাছে টাকা পাওনা নেই', 'Nobody owes you anything'],
    'saved': ['সংরক্ষণ হয়েছে', 'Saved'],
    'restricted_title': ['প্রথমে Android-এর একটি অনুমতি চালু করুন', 'First, unlock two settings in Android'],
    'restricted_steps': ['অ্যাপটি Play Store থেকে নয়, ফাইল থেকে ইনস্টল হয়েছে, তাই Android নোটিফিকেশন আর SMS-এর সুইচ আটকে রেখেছে। এটা স্বাভাবিক, ২ মিনিটে ঠিক হয়:\n\n১. নিচে "নোটিফিকেশন পড়া"-র "ঠিক করুন" চাপুন, তালিকায় এজেন্ট খাতা চাপুন, তারপর ধূসর সুইচটি চাপুন। Android বলবে "App was denied access" — বন্ধ করুন।\n২. এখানে ফিরে "অ্যাপের তথ্য খুলুন" চাপুন।\n৩. উপরে ডান কোণে ⋮ চাপুন → "Allow restricted settings" → ফোনের PIN দিন।\n৪. আবার "ঠিক করুন" চাপুন — এবার সুইচ চালু হবে।', 'The app was installed from a file, not the Play Store, so Android locks the notification and SMS switches. This is normal and takes 2 minutes:\n\n1. Tap Fix on "Read operator notifications" below, tap AgentKhata in the list, then tap the grey switch. Android says "App was denied access" — close it.\n2. Come back and tap "Open App info".\n3. Tap ⋮ in the top-right corner → "Allow restricted settings" → enter your phone PIN.\n4. Tap Fix again — the switch now turns on.'],
    'restricted_open': ['অ্যাপের তথ্য খুলুন', 'Open App info'],
    'lock_failed': ['যাচাই হয়নি, তাই লক চালু হয়নি। ফোনে স্ক্রিন লক (PIN বা আঙুলের ছাপ) আছে কিনা দেখুন।', 'Not verified, so the lock stays off. Check the phone has a screen lock (PIN or fingerprint).'],
    'shop_name_hint': ['যেমন: রহমান টেলিকম', 'e.g. Rahman Telecom'],
    'shop_owner': ['মালিকের নাম', 'Owner name'],
    'shop_address': ['ঠিকানা', 'Address'],
    'shop_address_hint': ['বাজার, উপজেলা, জেলা', 'Market, upazila, district'],
    'receipt_footer': ['রসিদের নিচের লেখা', 'Message at the bottom'],
    'connect_cancelled': ['সাইন-ইন শেষ হয়নি। আবার "যুক্ত করুন" চাপুন এবং ব্রাউজারে সাইন-ইন শেষ করুন।', 'Sign-in was not finished. Tap Connect again and complete the sign-in in the browser.'],
    'connect_exchange_failed': ['সাইন-ইন হয়েছে, কিন্তু ফোনটি যুক্ত করা যায়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।', 'Signed in, but the phone could not finish connecting. Check the internet and try again.'],
    'nav_entries': ['লেনদেন', 'Entries'],
    'update_available': ['নতুন সংস্করণ {v} এসেছে', 'Version {v} is available'],
    'update_sub': ['ডাউনলোড করে ইনস্টল করুন — আপনার হিসাব যেমন আছে তেমনই থাকবে', 'Download and install it — your books stay as they are'],
    'update_now': ['আপডেট', 'Update'],
    'update_latest': ['সর্বশেষ সংস্করণ চলছে', 'You have the latest version'],
    'update_check': ['দেখুন', 'Check'],
    'account_number': ['এজেন্ট নম্বর', 'Agent number'],
    'edit_wallet': ['অ্যাকাউন্ট সম্পাদনা', 'Edit account'],
    'no_account_number': ['নম্বর দেওয়া হয়নি — চাপুন', 'No number yet — tap to add'],
    'account_number_why': ['আপনার এজেন্ট নম্বর। একাধিক ফোন মিলিয়ে নিতে আর রসিদে দেখাতে লাগে।', "Your agent number. Used to match this account across phones and shown on receipts."],
    'exit_title': ['অ্যাপ বন্ধ করবেন?', 'Close the app?'],
    'exit_body': ['হিসাব ফোনেই থাকবে। ব্যাকগ্রাউন্ডে লেনদেন ধরা চালু থাকবে।', 'Your books stay on the phone, and transactions keep being recorded in the background.'],
    'stay': ['থাক', 'Stay'],
    'exit': ['বন্ধ করুন', 'Close'],
    'close_day': ['দিন শেষ করুন', 'Close the day'],
    'dayclose_adjustment': ['দিন শেষের সমন্বয়', 'Day close adjustment'],
    'dayclose_count_first': ['অন্তত একটি ব্যালান্স গুনে লিখুন', 'Count and type at least one balance'],
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
    // ---- setup: two ways in ----
    'setup_how': ['কীভাবে শুরু করবেন?', 'How are you starting?'],
    'setup_new_title': ['নতুন দোকান', 'A new shop'],
    'setup_new_sub': ['এটাই আমার প্রথম ফোন। ওয়ালেট আর ব্যালেন্স এখানে লিখব।', 'This is my first phone. I will set up wallets and balances here.'],
    'setup_join_title': ['দোকানে এই ফোন যোগ করুন', 'Add this phone to my shop'],
    'setup_join_sub': ['অন্য ফোনে এজেন্ট খাতা আগে থেকেই চলছে। এই ফোন বাকি ওয়ালেটগুলো ধরবে।', 'AgentKhata already runs on another phone. This one will capture the rest.'],
    'setup_join_signin': ['লগইন করে দোকানে যুক্ত হোন', 'Sign in to join your shop'],
    'setup_join_signin_sub': ['যে নম্বর দিয়ে দোকান খুলেছেন, সেটি দিয়ে লগইন করুন।', 'Sign in with the number you opened the shop with.'],
    'setup_join_failed': ['যুক্ত করা যায়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।', 'Could not join. Check the internet and try again.'],
    'setup_pick_captures': ['এই ফোনে কোন কোন ওয়ালেট আছে?', 'Which wallets are on this phone?'],
    'setup_pick_captures_sub': ['যেগুলোর অ্যাপ এই ফোনে আছে, সেগুলো আগে থেকেই টিক দেওয়া। এই ফোন শুধু এগুলোর লেনদেন লিখবে।', 'The ones whose apps are on this phone are already ticked. This phone records only these.'],
    'setup_found_app': ['অ্যাপ পাওয়া গেছে', 'App found on this phone'],
    'setup_capture_title': ['লেনদেন নিজে থেকে আসার জন্য', 'So transactions arrive by themselves'],
    'setup_capture_sub': ['প্রতিটি একবার চাপলেই হবে। সবুজ হলে ঠিক আছে।', 'Tap each once. Green means done.'],
    'check_notifications': ['অপারেটরের নোটিফিকেশন পড়ার অনুমতি', 'Read operator notifications'],
    'check_notifications_sub': ['বিকাশ/নগদ/রকেট অ্যাপের লেনদেন নিজে থেকে লিখবে। OTP বা PIN কখনো পড়া হয় না।', 'Records bKash/Nagad/Rocket app transactions. OTP and PIN are never read.'],
    'check_battery': ['ব্যাটারি সেভার যেন বন্ধ না করে', 'Keep running despite battery saver'],
    'check_battery_sub': ['না দিলে কয়েক ঘণ্টা পর ফোন এজেন্ট খাতা থামিয়ে দেয়, লেনদেন আর আসে না।', 'Without this, the phone stops AgentKhata after a few hours and entries stop.'],
    'check_autostart': ['ফোন চালু হলে নিজে চালু হবে', 'Start automatically'],
    'check_autostart_sub': ['এই ফোনের নিজস্ব "অটো স্টার্ট" তালিকায় এজেন্ট খাতা চালু করে দিন।', 'Turn AgentKhata on in this phone\'s own "Auto start" list.'],
    'check_autostart_done': ['করে দিয়েছি', 'Done it'],
    'check_sms': ['SMS পড়ার অনুমতি (ঐচ্ছিক)', 'Read SMS (optional)'],
    'check_sms_sub': ['অপারেটরের SMS থেকেও লেনদেন ধরবে। নোটিফিকেশন চালু থাকলে লাগে না।', 'Also captures from operator SMS. Not needed if notifications are on.'],
    'check_fix': ['ঠিক করুন', 'Fix'],
    'check_ok': ['ঠিক আছে', 'Done'],
    'health_title': ['এই ফোনের অবস্থা', 'This phone\'s health'],
    'health_banner': ['লেনদেন নিজে আসছে না — ঠিক করতে চাপুন', 'Transactions are not arriving by themselves — tap to fix'],
    'captures_title': ['এই ফোন যা ধরে', 'What this phone captures'],
    'captures_sub': ['অন্য ফোনের ওয়ালেট এখানে বন্ধ রাখুন, সেগুলো সেই ফোনই লিখবে।', 'Leave other phones\' wallets off here; those phones record them.'],
    'choose_account_title': ['কোন নম্বরটি এই ফোনে?', 'Which number is on this phone?'],
    'choose_account_sub': ['দোকানে একই অপারেটরের একাধিক নম্বর আছে।', 'The shop has more than one account with this operator.'],
    'hero_total': ['দোকানে এখন মোট', 'Money in the shop now'],
    'synced_ago': ['সিংক {when}', 'Synced {when}'],
    'syncing_now': ['সিংক হচ্ছে…', 'Syncing…'],
    'sync_offline': ['অফলাইন — সব ফোনেই আছে', 'Offline — all saved on the phone'],
    'sync_due': ['সাবস্ক্রিপশন বাকি', 'Subscription due'],
    'steady': ['ঠিক আছে', 'Steady'],
    'critical_float': ['প্রায় শেষ', 'Almost empty'],
    'just_now': ['এইমাত্র', 'just now'],
    'minutes_ago': ['{n} মিনিট আগে', '{n} min ago'],
    'hours_ago': ['{n} ঘণ্টা আগে', '{n} h ago'],
    'greet_morning': ['শুভ সকাল', 'Good morning'],
    'greet_noon': ['শুভ দুপুর', 'Good afternoon'],
    'greet_afternoon': ['শুভ বিকেল', 'Good afternoon'],
    'greet_evening': ['শুভ সন্ধ্যা', 'Good evening'],
    'greet_night': ['এখনো জেগে আছেন?', 'Working late?'],
    'qa_title': ['দ্রুত কাজ', 'Quick actions'],
    'qa_cash_in': ['ক্যাশ ইন', 'Cash in'],
    'qa_cash_out': ['ক্যাশ আউট', 'Cash out'],
    'qa_baki_give': ['বাকি দিন', 'Give credit'],
    'qa_baki_take': ['বাকি আদায়', 'Collect'],
    'qa_expense': ['খরচ', 'Expense'],
    'qa_dayclose': ['দিন শেষ', 'Close day'],
    'qa_reports': ['রিপোর্ট', 'Reports'],
    'qa_lift': ['লিফটিং চাই', 'Ask for float'],
    'lift_sheet_title': ['কোন ওয়ালেটে লিফটিং দরকার?', 'Which wallet needs float?'],
    'lift_none': ['এখন লাগবে না', 'Not needed now'],
    'lift_amount_open': ['কিছু টাকা', 'some float'],
    'stat_expenses': ['আজকের খরচ', 'Spent today'],
    'other_money': ['রিচার্জ ও ব্যাংক', 'Recharge & bank'],
    'trend_title': ['৭ দিনের কমিশন', 'Commission, last 7 days'],
    'trend_week': ['এই ৭ দিনে', 'these 7 days'],
    'vs_yesterday': ['গতকালের চেয়ে', 'vs yesterday'],
    'baki_widget': ['বাকি পাওনা', 'Owed to you'],
    'baki_none': ['কারো কাছে বাকি নেই', 'Nobody owes you'],
    'dayclose_done': ['আজকের হিসাব মেলানো হয়েছে', 'Today is counted and closed'],
    'dayclose_pending': ['দোকান বন্ধের সময় ড্রয়ার গুনে মেলান', 'Count the drawer at closing time'],
    'dayclose_yesterday_open': ['গতকালের দিন শেষ করা হয়নি', 'Yesterday was not closed'],
    'dayclose_go': ['মেলান', 'Close'],
    'runway_days': ['আর প্রায় {d} কর্মদিবস চলবে', 'Lasts about {d} working days'],
    'runway_month': ['এক মাসের বেশি চলবে', 'Lasts over a month'],
    'sync_error_plain': ['পাঠানো যায়নি — সব ফোনেই আছে, সংযোগ এলে আবার চেষ্টা করবে', 'Could not send — everything is kept on the phone and will retry'],
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

/// Replace `{name}` placeholders.
String fill(String template, Map<String, Object> values) {
  var out = template;
  values.forEach((key, value) => out = out.replaceAll('{$key}', '$value'));
  return out;
}

/// "5 minutes ago", in the reader's language and digits.
String agoText(DateTime at, String code) {
  final s = S(code);
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return s('just_now');
  if (minutes < 60) return fill(s('minutes_ago'), {'n': bnDigits('$minutes', code)});
  return fill(s('hours_ago'), {'n': bnDigits('${minutes ~/ 60}', code)});
}
