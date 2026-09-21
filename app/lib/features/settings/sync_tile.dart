import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/strings.dart';
import '../../platform/message_channel.dart';
import '../../sync/api_client.dart';
import '../../sync/sync_providers.dart';

/// Connecting this phone to CoreBari, and what the connection is doing.
///
/// The whole cloud story lives in one Settings row on purpose. An agent who
/// never taps it has a working app: capture, float, day close, baki and
/// reports all run on the phone alone. What tapping it buys is the portal, a
/// second phone, and a backup that survives losing this one — so the row says
/// that, rather than saying "sign in" and leaving them to guess why.
class SyncTile extends ConsumerWidget {
  const SyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;

    if (!ApiConfig.isConfigured) {
      return ListTile(
        leading: const Icon(Icons.cloud_off),
        title: Text(s('cloud_sync')),
        subtitle: Text(s('cloud_not_configured')),
      );
    }

    final token = ref.watch(deviceTokenProvider);
    if (token.isLoading) {
      return ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(s('cloud_sync')),
        subtitle: Text(s('loading')),
      );
    }

    if (token.value == null) return const _ConnectTile();

    return const _ConnectedTile();
  }
}

class _ConnectTile extends ConsumerStatefulWidget {
  const _ConnectTile();
  @override
  ConsumerState<_ConnectTile> createState() => _ConnectTileState();
}

class _ConnectTileState extends ConsumerState<_ConnectTile> {
  bool busy = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final s = ref.s;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(s('cloud_sync')),
          subtitle: Text(s('connect_why')),
          isThreeLine: true,
          trailing: busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonal(onPressed: _connect, child: Text(s('connect'))),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      /*
       * The name is what the owner sees on the portal's Devices screen and the
       * only thing distinguishing one phone from another when they go to
       * revoke a lost one. A model string is a poor name and still far better
       * than a uuid.
       */
      // The portal's phones page lists devices by this name; "Tecno Spark 20"
      // tells an owner which handset it is, "Android phone" three times does not.
      final identity = await MessageChannel.identity();
      final paired = await ref.read(deviceSessionProvider).pair(deviceName: identity?.model ?? 'Android phone');
      if (!paired) {
        setState(() => error = ref.s('connect_failed'));
        return;
      }
      ref.invalidate(deviceTokenProvider);
    } catch (_) {
      setState(() => error = ref.s('connect_failed'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _ConnectedTile extends ConsumerWidget {
  const _ConnectedTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final status = ref.watch(syncStatusProvider).value;
    final svc = ref.watch(syncServiceProvider);

    final (icon, color, text) = switch (status?.state) {
      'syncing' => (Icons.cloud_sync, Colors.blue, s('syncing')),
      'ok' => (Icons.cloud_done, Colors.green, '${s('synced')} ${DateFormat('h:mm a').format(status!.at!)}'),
      'read_only' => (Icons.lock_outline, Colors.orange, s('sync_read_only')),
      'unpaired' => (Icons.link_off, Colors.red, s('sync_unpaired')),
      'error' => (Icons.cloud_off, Colors.red, '${s('sync_error')}: ${status!.message}'),
      _ => (Icons.cloud_outlined, Colors.grey, s('idle')),
    };

    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: color),
          title: Text(s('cloud_sync')),
          subtitle: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(onPressed: svc?.syncNow, icon: const Icon(Icons.refresh)),
        ),
        ListTile(
          leading: const Icon(Icons.link_off),
          title: Text(s('disconnect')),
          subtitle: Text(s('disconnect_note')),
          onTap: () async {
            await ref.read(deviceSessionProvider).clear();
            ref.invalidate(deviceTokenProvider);
          },
        ),
      ],
    );
  }
}
