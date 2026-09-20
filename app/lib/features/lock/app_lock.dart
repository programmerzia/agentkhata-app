import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../l10n/strings.dart';

/// Locking the app behind the phone's own fingerprint or PIN.
///
/// ## Why this is worth having
///
/// An agent's phone sits on a counter all day and is handed to customers to
/// check a number. The app holds every balance the business has, the whole
/// baki book with names and phone numbers, and a device token that can write
/// to the books. A shutter that closes when the phone is put down is the
/// cheapest protection available for all of it.
///
/// ## Why it uses the device's own lock and not a PIN of ours
///
/// A PIN we store is a PIN we have to store safely, rate-limit, and offer a
/// reset for — and an agent who forgets it has lost their books. The phone
/// already has a credential the person knows, the OS already rate-limits it,
/// and `local_auth` falls back from fingerprint to that same device PIN
/// automatically. Inventing a second secret would be less safe and more work.
///
/// ## Why the app is usable with it off
///
/// It is off by default. An agent serving a customer every ninety seconds will
/// not unlock a phone every time, and a security control people turn off in
/// week one protects nobody. It earns its place for the agent who leaves the
/// counter, and is out of the way for the one who does not.
class AppLock {
  static const _enabledKey = 'agentkhata.lock_enabled';

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_enabledKey, value);

  /// Whether this phone can actually do it. A device with no fingerprint and
  /// no screen lock cannot, and offering the switch there is offering nothing.
  static Future<bool> isAvailable() async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: reason,
        // Device PIN is the fallback, not a refusal: a wet thumb at a counter
        // must not lock an agent out of their own books.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final lockEnabledProvider = FutureProvider<bool>((_) => AppLock.isEnabled());
final lockAvailableProvider = FutureProvider<bool>((_) => AppLock.isAvailable());

/// Wraps the app and holds the shutter closed until the person proves who they
/// are.
///
/// Re-locks when the app goes to the background rather than on a timer: the
/// moment that matters is the phone being put down or handed over, and that is
/// exactly what `paused` means.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      setState(() => _unlocked = false);
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await AppLock.authenticate(ref.read(localeProvider) == 'bn'
        ? 'এজেন্ট খাতা খুলতে যাচাই করুন'
        : 'Unlock AgentKhata');
    _prompting = false;
    if (mounted && ok) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(lockEnabledProvider).value ?? false;
    if (!enabled || _unlocked) return widget.child;

    final s = ref.s;
    // Prompt as soon as the shutter is shown, so the common case is one tap on
    // a fingerprint reader rather than two.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text(s('app'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(s('lock_prompt'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _unlock,
                icon: const Icon(Icons.fingerprint),
                label: Text(s('lock_unlock')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
