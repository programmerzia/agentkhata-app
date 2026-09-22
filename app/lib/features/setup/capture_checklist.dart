import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/strings.dart';
import '../../platform/message_channel.dart';

/// The phone's health, live: is capture on, and will it stay on?
///
/// Re-read on every return to the app, because every fix happens in a system
/// screen and the agent comes back here to see it turn green. Nothing to
/// remember, nothing to explain: each row says what it does in one line and
/// has one button that goes to exactly the right screen.
final phoneHealthProvider = FutureProvider.autoDispose<PhoneHealth?>((ref) async {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  return MessageChannel.health();
});

/// Manufacturers whose own "auto start" screen stops apps regardless of
/// Android's settings. On these, one more switch is needed; elsewhere the row
/// does not appear.
const _autostartMakers = {'xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'iqoo', 'tecno', 'infinix', 'itel', 'huawei', 'honor'};

class CaptureChecklist extends ConsumerStatefulWidget {
  const CaptureChecklist({super.key, this.dense = false});

  /// Tighter rows for the settings screen.
  final bool dense;

  @override
  ConsumerState<CaptureChecklist> createState() => _CaptureChecklistState();
}

class _CaptureChecklistState extends ConsumerState<CaptureChecklist> {
  static const _autostartKey = 'agentkhata.autostart_done';
  bool _autostartDone = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _autostartDone = prefs.getBool(_autostartKey) ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    final health = ref.watch(phoneHealthProvider).value;
    final maker = (health?.manufacturer ?? '').toLowerCase();
    final needsAutostart = _autostartMakers.any(maker.contains);

    final blocked = (health?.restrictedSettings ?? false) && !((health?.notificationAccess ?? false) && (health?.smsAccess ?? false));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (blocked) _RestrictedGuide(onOpen: MessageChannel.openAppDetails),
      _CheckRow(
        icon: Icons.notifications_active_outlined,
        title: s('check_notifications'),
        subtitle: s('check_notifications_sub'),
        ok: health?.notificationAccess ?? false,
        action: s('check_fix'),
        done: s('check_ok'),
        dense: widget.dense,
        // While Android is blocking it, this is still the first step: Android
        // only adds "Allow restricted settings" to App info after the person
        // has been refused once.
        onFix: MessageChannel.openNotificationAccessSettings,
      ),
      _CheckRow(
        icon: Icons.battery_charging_full_outlined,
        title: s('check_battery'),
        subtitle: s('check_battery_sub'),
        ok: health?.batteryUnrestricted ?? false,
        action: s('check_fix'),
        done: s('check_ok'),
        dense: widget.dense,
        onFix: () async {
          await MessageChannel.requestBatteryUnrestricted();
          ref.invalidate(phoneHealthProvider);
        },
      ),
      if (needsAutostart)
        _CheckRow(
          icon: Icons.restart_alt,
          title: s('check_autostart'),
          subtitle: s('check_autostart_sub'),
          // Android offers no way to read this switch back, so the agent's
          // own "done it" is the best signal there is.
          ok: _autostartDone,
          action: s('check_fix'),
          done: s('check_ok'),
          dense: widget.dense,
          onFix: () async {
            final opened = await MessageChannel.openAutostartSettings();
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_autostartKey, true);
            if (mounted) setState(() => _autostartDone = true);
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s('check_autostart_sub'))));
            }
          },
        ),
      _CheckRow(
        icon: Icons.sms_outlined,
        title: s('check_sms'),
        subtitle: s('check_sms_sub'),
        ok: health?.smsAccess ?? false,
        optional: true,
        action: s('check_fix'),
        done: s('check_ok'),
        dense: widget.dense,
        onFix: () async {
          final status = await Permission.sms.request();
          // Once refused twice Android stops showing the dialog and the
          // request returns at once: that is the "tap does nothing". Send the
          // person to the permission screen instead.
          if (!status.isGranted) await openAppSettings();
          ref.invalidate(phoneHealthProvider);
        },
      ),
    ]);
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.ok,
    required this.action,
    required this.done,
    required this.onFix,
    this.optional = false,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool ok;
  final bool optional;
  final bool dense;
  final String action;
  final String done;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = ok ? Colors.green.shade600 : (optional ? scheme.onSurfaceVariant : scheme.error);
    return Card(
      margin: EdgeInsets.symmetric(vertical: dense ? 3 : 6),
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(ok ? Icons.check_rounded : icon, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 8),
          ok
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(done, style: TextStyle(color: tone, fontWeight: FontWeight.w600)),
                )
              : FilledButton.tonal(onPressed: onFix, child: Text(action)),
        ]),
      ),
    );
  }
}

/// Shown above the checklist while Android is blocking the two capture
/// permissions for a file-installed app.
class _RestrictedGuide extends ConsumerWidget {
  const _RestrictedGuide({required this.onOpen});
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(child: Text(s('restricted_title'), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onErrorContainer))),
          ]),
          const SizedBox(height: 8),
          Text(s('restricted_steps'), style: TextStyle(color: scheme.onErrorContainer)),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.open_in_new), label: Text(s('restricted_open'))),
        ]),
      ),
    );
  }
}
