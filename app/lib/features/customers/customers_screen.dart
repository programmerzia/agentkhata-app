import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/core.dart';
import '../../l10n/strings.dart';
import 'baki_share.dart';

/// Baki (customer credit) ledger with free WhatsApp / SMS reminders.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final customers = ref.watch(customersProvider).value ?? [];
    final due = ref.watch(receivablesProvider);
    // Money owed to the shop only; a customer in credit is not a negative debt.
    final totalDue = due.values.fold<int>(0, (a, b) => b.value > 0 ? a + b.value : a);
    final sorted = [...customers]..sort((a, b) => (due[b.id]?.value ?? 0).compareTo(due[a.id]?.value ?? 0));

    return Scaffold(
      appBar: AppBar(title: Text(s('customers')), actions: [
        Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${s('due')}: ${Fmt.money(context, code, totalDue)}', style: const TextStyle(fontWeight: FontWeight.w700)))),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addCustomer(context, ref), icon: const Icon(Icons.person_add), label: Text(s('add_customer'))),
      body: customers.isEmpty
          ? Center(child: Text(s('add_customer')))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: sorted.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  final reachable = sorted.where((c) => (due[c.id]?.value ?? 0) > 0 && (c.phone?.isNotEmpty ?? false)).length;
                  if (reachable == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RemindersScreen())),
                      icon: const Icon(Icons.campaign_outlined),
                      label: Text('${s('remind_all')} (${bnDigits('$reachable', code)})'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  );
                }
                final c = sorted[i - 1];
                final d = due[c.id] ?? Paisa.zero;
                return ListTile(
                  leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                  title: Text(c.name),
                  subtitle: c.phone == null ? null : Text(bnDigits(c.phone!, code)),
                  trailing: Text(Fmt.money(context, code, d.value), style: TextStyle(fontWeight: FontWeight.w700, color: d.value > 0 ? Theme.of(context).colorScheme.error : Colors.green)),
                  onTap: () => _actions(context, ref, c, d),
                );
              },
            ),
    );
  }

  void _actions(BuildContext context, WidgetRef ref, Customer c, Paisa due) {
    final s = ref.s;
    final code = ref.read(localeProvider);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(c.name, style: Theme.of(context).textTheme.titleLarge), subtitle: Text('${s('due')}: ${Fmt.money(context, code, due.value)}')),
        ListTile(leading: const Icon(Icons.handshake_outlined), title: Text(s('give_baki')), onTap: () { Navigator.pop(context); context.push('/add?type=bakiGiven&customer=${c.id}'); }),
        ListTile(leading: const Icon(Icons.handshake), title: Text(s('receive_baki')), onTap: () { Navigator.pop(context); context.push('/add?type=bakiReceived&customer=${c.id}'); }),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(s('statement')),
          subtitle: Text(s('statement_sub')),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatementScreen(customer: c)));
          },
        ),
        if (c.phone != null && due.value > 0)
          ListTile(
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: Text('${s('remind')} (WhatsApp)'),
            onTap: () {
              remindOnWhatsApp(reminderText(s.call, code, c, due), c.phone!);
              Navigator.pop(context);
            },
          ),
        if (c.phone != null && due.value > 0)
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: Text('${s('remind')} (SMS)'),
            onTap: () {
              remindBySms(reminderText(s.call, code, c, due), c.phone!);
              Navigator.pop(context);
            },
          ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Future<void> _addCustomer(BuildContext context, WidgetRef ref) async {
    final s = ref.s;
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s('add_customer')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: s('name'))),
          const SizedBox(height: 8),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s('phone'))),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s('cancel'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s('save')))],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await ref.read(repositoryProvider).upsertCustomer(name: name.text.trim(), phone: phone.text.trim().isEmpty ? null : phone.text.trim());
    }
  }
}
