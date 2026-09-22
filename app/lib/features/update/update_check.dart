import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../l10n/strings.dart';
import '../../platform/message_channel.dart';
import '../../sync/api_client.dart';

/// Where the phone learns that a newer APK exists.
///
/// The app is not on the Play Store, so nothing else tells a shop its copy is
/// old. CoreBari's app page publishes the current release; the phone compares
/// version codes and offers the download. It never installs anything itself:
/// the agent taps, the browser downloads, Android asks.
///
/// Derived from the API host (agentkhata.corebari.net → corebari.net) so a
/// test build asks the test site and a production build the production one.
/// AGENTKHATA_UPDATES overrides it.
String updateFeedUrl() {
  const override = String.fromEnvironment('AGENTKHATA_UPDATES');
  if (override.isNotEmpty) return override;
  final api = Uri.tryParse(ApiConfig.baseUrl);
  if (api == null || api.host.isEmpty) return '';
  final host = api.host.startsWith('agentkhata.') ? api.host.substring('agentkhata.'.length) : api.host;
  return Uri(scheme: api.scheme, host: host, port: api.hasPort ? api.port : null, path: '/api/apps/agentkhata/android').toString();
}

class AppRelease {
  const AppRelease({required this.versionName, required this.versionCode, required this.apkUrl, this.notes});
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final Map<String, String>? notes;

  static AppRelease? fromJson(Map<String, dynamic> j) {
    final name = j['versionName'], code = j['versionCode'], url = j['apkUrl'];
    if (name is! String || code is! num || url is! String) return null;
    final uri = Uri.tryParse(url);
    // Only ever send the agent to an https download.
    if (uri == null || uri.scheme != 'https') return null;
    final notes = j['notes'];
    return AppRelease(
      versionName: name,
      versionCode: code.toInt(),
      apkUrl: url,
      notes: notes is Map ? notes.map((k, v) => MapEntry('$k', '$v')) : null,
    );
  }
}

class UpdateState {
  const UpdateState({required this.currentName, required this.currentCode, this.latest});
  final String currentName;
  final int currentCode;
  final AppRelease? latest;
  bool get available => latest != null && latest!.versionCode > currentCode;
}

const _checkedKey = 'agentkhata.update_checked_at';
const _cacheKey = 'agentkhata.update_latest';

/// Checked at most every six hours; the last answer is kept so the banner
/// survives a day with no internet.
final updateProvider = FutureProvider<UpdateState>((ref) async {
  final me = await MessageChannel.identity();
  final prefs = await SharedPreferences.getInstance();
  final state = UpdateState(currentName: me?.appVersion ?? '?', currentCode: me?.versionCode ?? 0);
  AppRelease? latest;
  final cached = prefs.getString(_cacheKey);
  if (cached != null) {
    try {
      latest = AppRelease.fromJson(jsonDecode(cached) as Map<String, dynamic>);
    } catch (_) {}
  }
  final last = DateTime.tryParse(prefs.getString(_checkedKey) ?? '');
  final url = updateFeedUrl();
  if (url.isNotEmpty && (last == null || DateTime.now().difference(last) > const Duration(hours: 6))) {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final fresh = AppRelease.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
        if (fresh != null) {
          latest = fresh;
          await prefs.setString(_cacheKey, res.body);
        }
      }
      await prefs.setString(_checkedKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Offline or the site is down: keep what we knew.
    }
  }
  return UpdateState(currentName: state.currentName, currentCode: state.currentCode, latest: latest);
});

Future<void> openDownload(AppRelease r) => launchUrl(Uri.parse(r.apkUrl), mode: LaunchMode.externalApplication);

/// A strip for the home screen, shown only when a newer version exists.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(updateProvider).value;
    if (u == null || !u.available) return const SizedBox.shrink();
    final s = ref.s;
    final code = ref.watch(localeProvider);
    final r = u.latest!;
    final note = r.notes?[code] ?? r.notes?['en'];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.system_update, color: scheme.onPrimaryContainer),
        title: Text(s('update_available').replaceAll('{v}', r.versionName), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
        subtitle: Text(note ?? s('update_sub'), style: TextStyle(color: scheme.onPrimaryContainer)),
        trailing: FilledButton(onPressed: () => openDownload(r), child: Text(s('update_now'))),
      ),
    );
  }
}

/// Settings: the real version, and a way to check now.
class AboutVersionTile extends ConsumerWidget {
  const AboutVersionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.s;
    final u = ref.watch(updateProvider);
    final state = u.value;
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text('AgentKhata ${state?.currentName ?? ''}'),
      subtitle: Text(state == null
          ? '…'
          : state.available
              ? s('update_available').replaceAll('{v}', state.latest!.versionName)
              : s('update_latest')),
      trailing: state?.available == true
          ? FilledButton(onPressed: () => openDownload(state!.latest!), child: Text(s('update_now')))
          : TextButton(
              onPressed: () async {
                final p = await SharedPreferences.getInstance();
                await p.remove(_checkedKey);
                ref.invalidate(updateProvider);
              },
              child: Text(s('update_check')),
            ),
    );
  }
}
