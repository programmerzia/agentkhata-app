import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/core.dart' as core;
import '../../data/ingestion_service.dart';

/// A bench for the capture pipeline, with no operator account anywhere.
///
/// ## Why this exists
///
/// Everything that makes this app worth installing happens when an operator
/// message arrives, and an operator message needs a live agent account with
/// real money moving through it. That is a terrible loop to debug in, and an
/// impossible one to hand to somebody who is evaluating the product. This
/// screen posts a message into the same [IngestionService] the notification
/// listener posts into, so the parser, the safety checks, deduplication, the
/// commission engine and the Unsorted inbox all run exactly as they will on a
/// real phone.
///
/// ## What it does NOT prove
///
/// The native half: whether Android actually delivers the notification, whether
/// the listener survives the phone's battery killer, whether the SMS receiver
/// is granted. Those need a real device and are covered in `docs/TESTING.md`.
/// This screen proves everything above the transport, which is where the
/// interesting behaviour lives.
///
/// ## Why it is debug-only
///
/// It writes to the same books as the real capture path. A tester wants that;
/// an agent must never find a button that invents transactions in their
/// ledger, so [SettingsScreen] only offers it when `kDebugMode` is true.
class MessageSimulatorScreen extends ConsumerStatefulWidget {
  const MessageSimulatorScreen({super.key});

  @override
  ConsumerState<MessageSimulatorScreen> createState() => _MessageSimulatorScreenState();
}

class _MessageSimulatorScreenState extends ConsumerState<MessageSimulatorScreen> {
  final _body = TextEditingController();
  final _sender = TextEditingController(text: 'bKash');
  final _log = <_Outcome>[];
  bool _busy = false;

  /// The last message that actually reached the books, exactly as it was sent.
  ///
  /// Kept whole — text, sender, package and source — because resending with a
  /// different sender is a different message. An earlier version resent the
  /// last log line using whatever was in the composer's sender field, which
  /// turned a quarantined message from a personal number into a legitimate one
  /// from bKash and posted it. The duplicate test then proved nothing and the
  /// books gained an entry the tester never asked for.
  _Sent? _lastPosted;

  @override
  void dispose() {
    _body.dispose();
    _sender.dispose();
    super.dispose();
  }

  /// Sends one message through the real pipeline and records the verdict.
  ///
  /// [freshIds] replaces the transaction id and the clock time in the canned
  /// text, because the second send of an identical message is caught by the
  /// deduplicator — correct behaviour that looks like a broken button unless
  /// you meant to test it, which is what [_sendAgain] is for.
  Future<void> _send(
    String body,
    String sender, {
    String? packageName,
    bool freshIds = true,
    core.TxSource source = core.TxSource.autoNotification,
  }) async {
    final sent = _Sent(
      body: freshIds ? _withFreshIds(body) : body,
      sender: sender,
      packageName: packageName,
      source: source,
    );
    setState(() => _busy = true);
    try {
      final result = await ref.read(ingestionProvider).ingest(
            body: sent.body,
            sender: sent.sender,
            packageName: sent.packageName,
            source: sent.source,
          );
      if (!mounted) return;
      setState(() {
        _log.insert(0, _Outcome(sent.body, result));
        if (result.status == core.ParseStatus.parsed) _lastPosted = sent;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The same message a second time, which is what a phone with both SMS and
  /// notification access sees for one transaction.
  ///
  /// Only a message that posted is worth resending: resending one that was
  /// ignored or quarantined re-runs that verdict and says nothing about
  /// deduplication, which is the thing under test.
  Future<void> _sendAgain() async {
    final last = _lastPosted;
    if (last == null) return;
    await _send(
      last.body,
      last.sender,
      packageName: last.packageName,
      source: last.source,
      freshIds: false,
    );
  }

  /// Twelve messages in the shape of a real evening: a rush of cash-ins and
  /// cash-outs across three operators, one duplicate, one message the parser
  /// cannot read and one fake.
  Future<void> _replayBusyHour() async {
    for (final scenario in _scenarios.where((s) => s.inReplay)) {
      await _send(
        scenario.body,
        scenario.sender,
        packageName: scenario.packageName,
        source: scenario.source,
      );
    }
    // Ends on a repeat of the last message that posted, which must be caught
    // as a duplicate rather than stored twice.
    await _sendAgain();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message simulator'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            onPressed: _log.isEmpty ? null : () => setState(_log.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Debug build only. These messages go through the real parser and '
                'land in the real books on this phone — use a test install, not '
                'one with a live khata in it.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _replayBusyHour,
            icon: const Icon(Icons.fast_forward),
            label: const Text('Replay a busy hour'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _lastPosted == null ? null : _sendAgain,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('Send the last one again (duplicate test)'),
          ),
          const Divider(height: 28),

          for (final group in _groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(group, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final s in _scenarios.where((s) => s.group == group))
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  title: Text(s.label),
                  subtitle: Text(s.expectation, style: Theme.of(context).textTheme.bodySmall),
                  trailing: const Icon(Icons.send_outlined),
                  onTap: _busy
                      ? null
                      : () => _send(s.body, s.sender, packageName: s.packageName, source: s.source),
                  onLongPress: () {
                    // Long press loads it into the composer instead of sending,
                    // so a tester can mangle a real shape rather than type one.
                    _body.text = s.body;
                    _sender.text = s.sender;
                    setState(() {});
                  },
                ),
              ),
          ],

          const Divider(height: 28),
          Text('Your own text', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _sender,
            decoration: const InputDecoration(labelText: 'Sender', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Message body',
              hintText: 'Paste a real operator message here',
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy || _body.text.trim().isEmpty
                    ? null
                    : () => _send(_body.text, _sender.text, freshIds: false),
                child: const Text('Send as notification'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _body.text.trim().isEmpty
                    ? null
                    : () => _send(_body.text, _sender.text,
                        freshIds: false, source: core.TxSource.autoSms),
                child: const Text('Send as SMS'),
              ),
            ),
          ]),

          if (_log.isNotEmpty) ...[
            const Divider(height: 28),
            Text('What happened', style: Theme.of(context).textTheme.titleSmall),
            for (final outcome in _log)
              ListTile(
                dense: true,
                leading: Icon(outcome.icon, color: outcome.color(context)),
                title: Text(outcome.headline),
                subtitle: Text(outcome.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ],
      ),
    );
  }
}

/// Fresh transaction id and clock time, so repeated sends are separate events.
String _withFreshIds(String body) {
  final rnd = Random();
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
  final trx = List.generate(10, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return body
      .replaceAll('{trx}', trx)
      .replaceAll('{date}', '${two(now.day)}/${two(now.month)}/${now.year}')
      .replaceAll('{dashdate}', '${two(now.day)}-${two(now.month)}-${now.year}')
      .replaceAll('{time}', '${two(now.hour)}:${two(now.minute)}');
}

/// One message exactly as it went in, so it can go in again unchanged.
class _Sent {
  const _Sent({
    required this.body,
    required this.sender,
    required this.packageName,
    required this.source,
  });

  final String body;
  final String sender;
  final String? packageName;
  final core.TxSource source;
}

class _Outcome {
  _Outcome(this.body, this.result);
  final String body;
  final IngestResult result;

  String get headline => switch (result.status) {
        core.ParseStatus.parsed => 'Posted to the books',
        core.ParseStatus.unparsed => 'Unsorted: ${result.reason ?? 'not understood'}',
        core.ParseStatus.duplicate => 'Duplicate, stored once',
        core.ParseStatus.suspicious => 'Quarantined as suspicious',
        core.ParseStatus.ignored => 'Ignored: ${result.reason ?? 'not a transaction'}',
      };

  IconData get icon => switch (result.status) {
        core.ParseStatus.parsed => Icons.check_circle_outline,
        core.ParseStatus.unparsed => Icons.inbox_outlined,
        core.ParseStatus.duplicate => Icons.copy_all_outlined,
        core.ParseStatus.suspicious => Icons.gpp_maybe_outlined,
        core.ParseStatus.ignored => Icons.block_outlined,
      };

  Color color(BuildContext context) => switch (result.status) {
        core.ParseStatus.parsed => Colors.green.shade600,
        core.ParseStatus.suspicious => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };
}

class _Scenario {
  const _Scenario({
    required this.group,
    required this.label,
    required this.expectation,
    required this.sender,
    required this.body,
    this.packageName,
    this.source = core.TxSource.autoNotification,
    this.inReplay = false,
  });

  final String group;
  final String label;

  /// What a tester should see. Written as the expected verdict, so this screen
  /// doubles as the test script: tap down the list and any row whose outcome
  /// disagrees with its subtitle is a bug.
  final String expectation;
  final String sender;
  final String body;
  final String? packageName;
  final core.TxSource source;
  final bool inReplay;
}

const _groups = ['Normal traffic', 'Edge cases', 'Safety'];

/// The shapes the parser is built for, one per behaviour worth seeing.
const _scenarios = <_Scenario>[
  _Scenario(
    group: 'Normal traffic',
    label: 'bKash cash in, Tk 1,000',
    expectation: 'Posts to the bKash wallet, commission from the rate table',
    sender: 'bKash',
    inReplay: true,
    body:
        'Cash In Tk 1,000.00 to 01712345678 successful. Fee Tk 0.00. Balance Tk 25,340.50. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'bKash cash out with stated commission',
    expectation: 'Posts with Tk 2.05 commission, the operator number winning over the rule',
    sender: 'bKash',
    inReplay: true,
    body:
        'Cash Out Tk 500.00 from 01812345678 successful. Fee Tk 0.00. Comm Tk 2.05. Balance Tk 25,842.55. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'bKash agent app notification',
    expectation: 'Posts; recognised by package name with no sender at all',
    sender: '',
    packageName: 'com.bkash.businessapp',
    inReplay: true,
    body: 'Cash In Tk 200.00 to 01712345678 successful. Balance Tk 100.00. TrxID {trx}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'Nagad cash in',
    expectation: 'Posts to the Nagad wallet, colon-separated fields',
    sender: 'NAGAD',
    inReplay: true,
    body:
        'Cash In Tk 2,000.00 to 01512345678 successful. Comm: Tk 8.20. Balance: Tk 12,345.67. TxnID: {trx}. {date} {time}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'Rocket cash in, compact format (as SMS)',
    expectation: 'Posts to Rocket; 12-digit account, no space after Tk, source SMS',
    sender: '16216',
    source: core.TxSource.autoSms,
    inReplay: true,
    body:
        'Cash In Tk500.00 to A/C 017123456789 successful. Fee Tk0.00. Comm Tk2.08. Bal Tk8,500.00. TxnId {trx} at {dashdate} {time}:33',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'Upay cash out',
    expectation: 'Posts to Upay',
    sender: 'upay',
    inReplay: true,
    body:
        'Cash Out of Tk 700.00 from 01412345678 is successful. Fee Tk 0.00. Balance Tk 3,300.00. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'B2B lifting received, Tk 50,000',
    expectation: 'Float jumps and the drawer drops: lifting is paid for in cash',
    sender: '16247',
    inReplay: true,
    body:
        'You have received B2B Tk 50,000.00 from 01912345678. Balance Tk 75,842.55. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Normal traffic',
    label: 'Payment received, Tk 300',
    expectation: 'Posts as a payment, not a cash in',
    sender: 'bKash',
    inReplay: true,
    body:
        'You have received payment Tk 300.00 from 01612345678. Balance Tk 76,142.55. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Edge cases',
    label: 'Bangla numerals in the amount',
    expectation: 'Posts Tk 1,000 — the digits are converted, not dropped',
    sender: 'bKash',
    body:
        'Cash In Tk ১,০০০.০০ to 01712345678 successful. Balance Tk ৫,০০০.০০. TrxID {trx}',
  ),
  _Scenario(
    group: 'Edge cases',
    label: 'Wording the parser has never seen',
    expectation: 'Unsorted, nothing posted — the whole point of the inbox',
    sender: 'bKash',
    inReplay: true,
    body: 'Your agent wallet has been topped up by Tk 4,500.00 ref {trx}',
  ),
  _Scenario(
    group: 'Edge cases',
    label: 'Operator with no wallet configured',
    expectation: 'Unsorted with "no wallet configured", if you have no Upay wallet',
    sender: 'upay',
    body:
        'Cash In Tk 900.00 to 01412345678 is successful. Balance Tk 2,400.00. TrxID {trx} at {date} {time}',
  ),
  _Scenario(
    group: 'Edge cases',
    label: 'Failed transaction',
    expectation: 'Ignored — a failure moved no money',
    sender: 'bKash',
    body: 'Cash Out Tk 500.00 from 01812345678 failed. Balance Tk 25,842.55.',
  ),
  _Scenario(
    group: 'Safety',
    label: 'OTP message',
    expectation: 'Ignored and never stored, not even in Unsorted',
    sender: 'bKash',
    inReplay: true,
    body: 'Your bKash OTP is 123456. Do not share it with anyone.',
  ),
  _Scenario(
    group: 'Safety',
    label: 'Fake "payment received" from a personal number',
    expectation: 'Quarantined as suspicious; this is the scam agents lose money to',
    sender: '01799887766',
    inReplay: true,
    body:
        'Cash In Tk 5,000.00 to 01712345678 successful. Balance Tk 25,340.50. TrxID {trx} at {date} {time} bKash',
  ),
  _Scenario(
    group: 'Safety',
    label: 'Marketing blast',
    expectation: 'Ignored',
    sender: 'bKash',
    body: 'Congratulations! Get 10% cashback offer on bKash payment this Eid.',
  ),
];
