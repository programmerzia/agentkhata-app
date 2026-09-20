import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/strings.dart';

/// The distributor's number, stored once so asking for float is one tap.
///
/// Lifting is the thing an agent does when a wallet runs low, and the current
/// way is to stop, find the distributor in a contact list, and type a message
/// with a number in it. The float dashboard already computes what to ask for;
/// this is the missing half.
///
/// Kept in plain preferences rather than synced: it is one phone number that
/// belongs to this device's owner, and a distributor differs between counters
/// of the same business.
class TopUpNumberTile extends ConsumerStatefulWidget {
  const TopUpNumberTile({super.key});

  static const prefsKey = 'agentkhata.distributor_phone';

  static Future<String?> number() async =>
      (await SharedPreferences.getInstance()).getString(prefsKey);

  @override
  ConsumerState<TopUpNumberTile> createState() => _TopUpNumberTileState();
}

class _TopUpNumberTileState extends ConsumerState<TopUpNumberTile> {
  final controller = TextEditingController();
  bool saved = false;

  @override
  void initState() {
    super.initState();
    TopUpNumberTile.number().then((value) {
      if (value != null && mounted) controller.text = value;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    return ListTile(
      leading: const Icon(Icons.local_shipping_outlined),
      title: Text(s('topup_number')),
      subtitle: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(saved ? Icons.check : Icons.save_outlined),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(TopUpNumberTile.prefsKey, controller.text.trim());
              if (mounted) setState(() => saved = true);
            },
          ),
        ),
      ),
    );
  }
}

/// Putting the widget on the home screen from inside the app.
///
/// Discovery is the whole reason this exists: most agents have never held down
/// an empty patch of launcher to find a widget tray, so the feature would go
/// unused while being the fastest thing in the product. Android decides whether
/// pinning is allowed, and when it is not the tile stays away rather than
/// offering a button that does nothing.
class WidgetPinTile extends ConsumerStatefulWidget {
  const WidgetPinTile({super.key});

  @override
  ConsumerState<WidgetPinTile> createState() => _WidgetPinTileState();
}

class _WidgetPinTileState extends ConsumerState<WidgetPinTile> {
  bool supported = false;

  @override
  void initState() {
    super.initState();
    HomeWidget.isRequestPinWidgetSupported().then((value) {
      if (mounted) setState(() => supported = value ?? false);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (!supported) return const SizedBox.shrink();
    final s = ref.s;
    return ListTile(
      leading: const Icon(Icons.widgets_outlined),
      title: Text(s('widget_add')),
      subtitle: Text(s('widget_desc')),
      onTap: () => HomeWidget.requestPinWidget(
        name: 'HomeScreenWidget',
        androidName: 'HomeScreenWidget',
      ),
    );
  }
}
