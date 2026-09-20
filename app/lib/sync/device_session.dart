import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'api_client.dart';

/// The device token, and the pairing that obtains one.
///
/// ## Where the token lives
///
/// `flutter_secure_storage`, which on Android is Keystore-backed. Not the
/// ordinary preferences file: this token is a bearer credential for a
/// business's books, and a rooted phone or an adb backup reads plain
/// preferences without effort.
///
/// ## The pairing flow
///
/// 1. The app opens `<server>/pair?name=<model>` in a Custom Tab.
/// 2. The web app signs the person in through CoreBari, creates a device row
///    and mints a token, then redirects to `agentkhata://paired#code=...`.
/// 3. The tab closes, this class receives the code, and POSTs it back to
///    exchange it for the token over TLS.
///
/// The code rather than the token travels in the deep link because a custom
/// URL scheme is not exclusive on Android — another installed app can claim
/// `agentkhata://` too. The code is single-use and expires in two minutes, so
/// the worst an interceptor gets is a pairing that visibly fails.
class DeviceSession {
  DeviceSession({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'agentkhata.device_token';
  static const _tenantKey = 'agentkhata.tenant_id';
  static const callbackScheme = 'agentkhata';

  Future<String?> token() => _storage.read(key: _tokenKey);
  Future<String?> tenantId() => _storage.read(key: _tenantKey);

  Future<bool> get isPaired async => (await token()) != null;

  Future<void> save({required String token, required String tenantId}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _tenantKey, value: tenantId);
  }

  /// Forget this device's credentials. Local books are untouched — an agent
  /// who disconnects keeps every entry on the phone and can pair again.
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _tenantKey);
  }

  /// Run the pairing round trip. Returns false if the person cancelled.
  Future<bool> pair({required String deviceName}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/pair')
        .replace(queryParameters: {'name': deviceName}).toString();

    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
      );
    } catch (_) {
      // The person closed the tab, or the system had no browser to open.
      return false;
    }

    /*
     * The code arrives in the FRAGMENT, not the query. A fragment is never
     * sent to a server, so it cannot end up in an access log on the way — and
     * the redirect that carries it passes through whatever the phone's default
     * browser is.
     */
    final fragment = Uri.parse(result).fragment;
    final code = Uri.splitQueryString(fragment)['code'];
    if (code == null || code.isEmpty) return false;

    final exchanged = await ApiClient.exchangePairingCode(code);
    if (exchanged == null) return false;

    await save(token: exchanged.token, tenantId: exchanged.tenantId);
    return true;
  }
}
