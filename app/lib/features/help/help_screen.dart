import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../l10n/strings.dart';

/// Help, in the words an agent uses.
///
/// ## Why written answers and not videos
///
/// A video needs a shop with data to spare and a hand free to hold the phone,
/// and an agent opens help with a customer at the counter. Text is skimmable,
/// works on a 2G connection because it ships inside the app, and costs nothing
/// to read twice. Videos can come later beside these answers; the answers are
/// what unblocks somebody today.
///
/// ## Why the content is here rather than fetched
///
/// The commonest reason to open help is that something is not working, and a
/// help screen that needs the network to explain a network problem is a joke.
/// Every answer below is compiled into the app.
class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final bn = code == 'bn';

    return Scaffold(
      appBar: AppBar(title: Text(s('help'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
        children: [
          for (final topic in _topics)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ExpansionTile(
                leading: Icon(topic.icon),
                title: Text(bn ? topic.titleBn : topic.title),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      bn ? topic.bodyBn : topic.body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Topic {
  const _Topic({
    required this.icon,
    required this.title,
    required this.titleBn,
    required this.body,
    required this.bodyBn,
  });

  final IconData icon;
  final String title;
  final String titleBn;
  final String body;
  final String bodyBn;
}

/// The eight questions support actually gets asked, in the order they arrive.
const _topics = <_Topic>[
  _Topic(
    icon: Icons.bolt_outlined,
    title: 'Entries are not appearing by themselves',
    titleBn: 'লেনদেন নিজে নিজে আসছে না',
    body:
        'The app reads the notifications your operator apps post. Open Settings, '
        'tap Notification access and switch it on for AgentKhata. Then make one '
        'small transaction and watch the home screen. If your phone silences '
        'operator notifications to save battery, remove AgentKhata from battery '
        'optimisation as well.',
    bodyBn:
        'অপারেটর অ্যাপ যে নোটিফিকেশন দেয়, অ্যাপ সেটা পড়ে হিসাব লেখে। সেটিংসে গিয়ে '
        'নোটিফিকেশন অ্যাক্সেস চালু করুন। এরপর ছোট একটা লেনদেন করে হোম স্ক্রিন দেখুন। '
        'ফোন যদি ব্যাটারি বাঁচাতে নোটিফিকেশন বন্ধ রাখে, তাহলে ব্যাটারি অপটিমাইজেশন থেকেও '
        'এজেন্ট খাতা বাদ দিন।',
  ),
  _Topic(
    icon: Icons.inbox_outlined,
    title: 'A message went to Unsorted',
    titleBn: 'মেসেজ অমীমাংসিত তালিকায় গেছে',
    body:
        'That means the app was not sure what the message said, so it refused to '
        'guess. Open Unsorted, tap the message, choose the wallet and type, and '
        'save. Nothing is lost and no wrong number was ever posted. Operators '
        'change their wording from time to time and the app learns the new shape '
        'through an update.',
    bodyBn:
        'মেসেজের অর্থ অ্যাপ নিশ্চিত বুঝতে পারেনি, তাই অনুমান করেনি। অমীমাংসিত তালিকা '
        'খুলে মেসেজে চাপ দিন, ওয়ালেট আর ধরন বেছে সংরক্ষণ করুন। কিছুই হারায়নি, ভুল '
        'হিসাবও বসেনি। অপারেটর মাঝে মাঝে মেসেজের ভাষা বদলায়, আপডেটে অ্যাপ সেটা শিখে নেয়।',
  ),
  _Topic(
    icon: Icons.account_balance_wallet_outlined,
    title: 'The balance does not match my operator app',
    titleBn: 'ব্যালেন্স অপারেটর অ্যাপের সাথে মিলছে না',
    body:
        'Check three things. First, an entry still sitting in Unsorted has not '
        'moved any balance yet. Second, the opening balance of the wallet: set it '
        'once, on the day you start, from the operator app. Third, a transaction '
        'made from another phone or the operator app itself arrives only if a '
        'notification for it reached this phone.',
    bodyBn:
        'তিনটি জিনিস দেখুন। এক, অমীমাংসিত তালিকায় থাকা লেনদেন এখনো ব্যালেন্স বদলায়নি। '
        'দুই, ওয়ালেটের শুরুর ব্যালেন্স — শুরুর দিন অপারেটর অ্যাপ দেখে একবার বসাতে হয়। '
        'তিন, অন্য ফোন বা অপারেটর অ্যাপ থেকে করা লেনদেন এই ফোনে নোটিফিকেশন এলেই যোগ হয়।',
  ),
  _Topic(
    icon: Icons.lock_clock_outlined,
    title: 'How day close works',
    titleBn: 'দিন শেষের হিসাব যেভাবে কাজ করে',
    body:
        'Count the cash in your drawer and type that number. The app already '
        'knows what the drawer should hold, so it shows the difference and the '
        'entries around it that are worth a second look. Close the day and it is '
        'locked: later edits are recorded, never silent.',
    bodyBn:
        'ড্রয়ারের নগদ গুনে সেই সংখ্যাটা লিখুন। ড্রয়ারে কত থাকা উচিত অ্যাপ জানে, তাই '
        'পার্থক্য আর সন্দেহজনক লেনদেনগুলো দেখায়। দিন শেষ করলে সেটি লক হয়ে যায় — পরে '
        'কিছু বদলালে তা রেকর্ড হয়, চুপচাপ বদলায় না।',
  ),
  _Topic(
    icon: Icons.people_outline,
    title: 'Baki and reminders',
    titleBn: 'বাকি আর তাগাদা',
    body:
        'Add credit with Baki given and settle it with Baki received. The due is '
        'always added up from those entries, so correcting a mistake corrects the '
        'due. Reminders open WhatsApp with the text ready; you press send, so '
        'nothing goes out behind your back and it costs nothing.',
    bodyBn:
        'বাকি দিলে "বাকি দেওয়া", টাকা ফেরত পেলে "বাকি আদায়" লিখুন। পাওনা সবসময় এই '
        'লেনদেনগুলো যোগ করে বের হয়, তাই ভুল শুধরালে পাওনাও ঠিক হয়ে যায়। তাগাদার লেখা '
        'তৈরি হয়ে হোয়াটসঅ্যাপে খোলে, পাঠাবেন আপনি — আপনার অগোচরে কিছু যায় না, খরচও নেই।',
  ),
  _Topic(
    icon: Icons.cloud_outlined,
    title: 'Do I need an account?',
    titleBn: 'অ্যাকাউন্ট লাগবে কি?',
    body:
        'No. The app keeps your whole khata on this phone and works with no '
        'network at all. Connect to CoreBari later if you want the web portal, a '
        'second phone at another counter, or staff with their own login.',
    bodyBn:
        'না। পুরো খাতা এই ফোনেই থাকে, ইন্টারনেট ছাড়াই চলে। ওয়েব পোর্টাল, আরেক '
        'কাউন্টারে দ্বিতীয় ফোন, বা কর্মীর আলাদা লগইন লাগলে পরে কোরবাড়ির সাথে যুক্ত করুন।',
  ),
  _Topic(
    icon: Icons.sync_outlined,
    title: 'What syncing does and does not send',
    titleBn: 'সিংক কী পাঠায়, কী পাঠায় না',
    body:
        'Your entries, wallets, customers and day closes travel to your own '
        'business on CoreBari. A PIN or OTP is never stored anywhere, not even on '
        'this phone: the app drops it the moment it reads a message. Raw operator '
        'messages are uploaded only if you switch that on yourself.',
    bodyBn:
        'আপনার লেনদেন, ওয়ালেট, গ্রাহক আর দিন শেষের হিসাব কোরবাড়িতে আপনার নিজের '
        'ব্যবসার অংশ হিসেবে যায়। পিন বা ওটিপি কোথাও রাখা হয় না, এই ফোনেও না — মেসেজ '
        'পড়ার সাথে সাথেই বাদ দেওয়া হয়। অপারেটরের মূল মেসেজ শুধু আপনি নিজে চালু করলে যায়।',
  ),
  _Topic(
    icon: Icons.save_outlined,
    title: 'Changing phones without losing the khata',
    titleBn: 'ফোন বদলালে খাতা যাতে না হারায়',
    body:
        'If you are connected to CoreBari, sign in on the new phone and the khata '
        'comes down by itself. If you are not, use Backup in Settings to write a '
        'file, copy it across, and use Restore. Do it before the old phone leaves '
        'your hand.',
    bodyBn:
        'কোরবাড়ির সাথে যুক্ত থাকলে নতুন ফোনে লগইন করলেই খাতা নিজে নেমে আসে। যুক্ত না '
        'থাকলে সেটিংসের ব্যাকআপ দিয়ে ফাইল বানান, নতুন ফোনে কপি করে রিস্টোর করুন। পুরনো '
        'ফোন হাতছাড়া করার আগেই কাজটা সেরে ফেলুন।',
  ),
];
