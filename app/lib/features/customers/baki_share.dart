import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import '../receipts/receipt.dart';

/// The reminder text for one customer, in the app's language.
String reminderText(String Function(String) s, String code, Customer c, Paisa due) =>
    s('statement_msg').replaceAll('{name}', c.name).replaceAll('{amt}', Fmt.moneyOf(code, due.value));

Future<void> remindOnWhatsApp(String text, String phone) =>
    launchUrl(Uri.parse('https://wa.me/${intlBd(phone)}?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);

Future<void> remindBySms(String text, String phone) => launchUrl(Uri(scheme: 'sms', path: phone, queryParameters: {'body': text}));

/// One customer's baki, line by line, ready to send as a PDF or picture.
class StatementScreen extends ConsumerStatefulWidget {
  const StatementScreen({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share(bool pdf, Paisa due) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final code = ref.read(localeProvider);
      await shareRendered(_key, name: 'statement-${widget.customer.name}', text: reminderText(ref.s.call, code, widget.customer, due), pdf: pdf);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final c = widget.customer;
    final due = ref.watch(receivablesProvider)[c.id] ?? Paisa.zero;
    return Scaffold(
      appBar: AppBar(title: Text(s('statement'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: RepaintBoundary(key: _key, child: StatementCard(customer: c))),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : () => _share(true, due),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(s('share_pdf_statement')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _share(false, due), icon: const Icon(Icons.image_outlined), label: Text(s('share_image')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)))),
          if (c.phone != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => remindOnWhatsApp(reminderText(s.call, code, c, due), c.phone!),
                icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                label: const Text('WhatsApp'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text(s('share_hint'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class StatementCard extends ConsumerWidget {
  const StatementCard({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final header = ref.watch(receiptHeaderProvider).value;
    final lines = [
      for (final t in ref.watch(postedProvider))
        if (t.customerId == customer.id && (t.type == TxType.bakiGiven || t.type == TxType.bakiReceived)) t,
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    // Running balance oldest first; show the latest 25 so the picture stays
    // readable, with everything before folded into "brought forward".
    var running = 0;
    final rows = <(Transaction, int)>[];
    for (final t in lines) {
      running += t.type == TxType.bakiGiven ? t.amount.value : -t.amount.value;
      rows.add((t, running));
    }
    final shown = rows.length > 25 ? rows.sublist(rows.length - 25) : rows;
    final forward = rows.length > 25 ? rows[rows.length - 26].$2 : null;
    final df = DateFormat('d MMM yy', code == 'bn' ? 'bn' : 'en');
    const ink = Colors.black87, faint = Colors.black54;
    TextStyle st(double size, {FontWeight w = FontWeight.w500, Color c = ink}) => TextStyle(color: c, fontSize: size, fontWeight: w);
    Widget line(String a, String b, String c, String d, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 70, child: Text(a, style: st(11, c: head ? faint : ink))),
            Expanded(child: Text(b, textAlign: TextAlign.end, style: st(11, c: head ? faint : ink))),
            Expanded(child: Text(c, textAlign: TextAlign.end, style: st(11, c: head ? faint : ink))),
            Expanded(child: Text(d, textAlign: TextAlign.end, style: st(11, w: FontWeight.w700, c: head ? faint : ink))),
          ]),
        );
    return Container(
      width: 340,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ShopHeaderBlock(header: header, code: code),
        const SizedBox(height: 4),
        Text(s('statement').toUpperCase(), textAlign: TextAlign.center, style: st(10, c: faint).copyWith(letterSpacing: code == 'bn' ? 0 : 2)),
        const Divider(color: Colors.black26, height: 22),
        Text(customer.name, style: st(15, w: FontWeight.w700)),
        if (customer.phone != null) Text(bnDigits(customer.phone!, code), style: st(11, c: faint)),
        Text('${s('as_of')} ${bnDigits(DateFormat('d MMM yyyy', code == 'bn' ? 'bn' : 'en').format(DateTime.now()), code)}', style: st(11, c: faint)),
        const SizedBox(height: 10),
        line(s('date'), s('baki_given_short'), s('paid_short'), s('balance'), head: true),
        const Divider(color: Colors.black12, height: 6),
        if (forward != null) line('', s('brought_forward'), '', Fmt.moneyOf(code, forward)),
        for (final (t, bal) in shown)
          line(
            bnDigits(df.format(t.occurredAt), code),
            t.type == TxType.bakiGiven ? Fmt.moneyOf(code, t.amount.value) : '',
            t.type == TxType.bakiReceived ? Fmt.moneyOf(code, t.amount.value) : '',
            Fmt.moneyOf(code, bal),
          ),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s('no_baki_yet'), textAlign: TextAlign.center, style: st(12, c: faint))),
        const Divider(color: Colors.black26, height: 22),
        Row(children: [
          Expanded(child: Text(s('total_due'), style: st(14, w: FontWeight.w700))),
          Text(Fmt.moneyOf(code, running), style: st(18, w: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

/// Everyone who owes and has a number, with a WhatsApp and an SMS button
/// each. The app cannot press send for the agent (and should not); it can
/// make each reminder one tap and remember who has been reminded today.
class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  final sent = <String>{};

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final due = ref.watch(receivablesProvider);
    final customers = ref.watch(customersProvider).value ?? [];
    final owing = [for (final c in customers) if ((due[c.id]?.value ?? 0) > 0) c]..sort((a, b) => due[b.id]!.value.compareTo(due[a.id]!.value));
    final reachable = owing.where((c) => c.phone != null && c.phone!.isNotEmpty).toList();
    final noPhone = owing.length - reachable.length;
    return Scaffold(
      appBar: AppBar(title: Text(s('remind_all'))),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            s('remind_all_sub').replaceAll('{n}', bnDigits('${reachable.length}', code)).replaceAll('{done}', bnDigits('${sent.length}', code)),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        for (final c in reachable)
          ListTile(
            leading: CircleAvatar(child: sent.contains(c.id) ? const Icon(Icons.check) : Text(c.name.characters.first)),
            title: Text(c.name),
            subtitle: Text(Fmt.moneyOf(code, due[c.id]!.value)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'WhatsApp',
                icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                onPressed: () {
                  setState(() => sent.add(c.id));
                  remindOnWhatsApp(reminderText(s.call, code, c, due[c.id]!), c.phone!);
                },
              ),
              IconButton(
                tooltip: 'SMS',
                icon: const Icon(Icons.sms_outlined),
                onPressed: () {
                  setState(() => sent.add(c.id));
                  remindBySms(reminderText(s.call, code, c, due[c.id]!), c.phone!);
                },
              ),
            ]),
          ),
        if (noPhone > 0)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s('remind_no_phone').replaceAll('{n}', bnDigits('$noPhone', code)), style: Theme.of(context).textTheme.bodySmall),
          ),
        if (owing.isEmpty) Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s('nobody_owes')))),
      ]),
    );
  }
}
