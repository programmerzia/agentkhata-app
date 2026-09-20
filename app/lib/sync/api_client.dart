import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the AgentKhata server lives.
///
/// Set at build time:
///   flutter build apk --dart-define=AGENTKHATA_API=https://agentkhata.corebari.com
///
/// The default is the Android emulator's alias for the host machine, which is
/// what a developer running the portal on :3127 needs. A physical phone on the
/// same Wi-Fi uses the PC's LAN IP instead, and production passes the real
/// host — so no build of this app has a server address baked in that a
/// deployment cannot change.
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'AGENTKHATA_API',
    defaultValue: 'http://10.0.2.2:3127',
  );

  /// True when a server has been configured at all. When false the app runs
  /// fully offline and hides every cloud feature rather than showing buttons
  /// that cannot work.
  static bool get isConfigured => baseUrl.isNotEmpty;
}

/// Thrown when the server answers, but not with success.
class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  /// The subscription lapsed. Distinct from every other failure because the
  /// app says something completely different about it: the books are safe,
  /// nothing was lost, pay to resume.
  bool get isReadOnly => statusCode == 402;

  /// The device token was revoked or is unknown. The app must re-pair.
  bool get isUnauthorised => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// The HTTP client for the mobile API.
///
/// Deliberately thin: it holds the base URL and the device token, attaches the
/// bearer header, and turns a non-2xx into an exception the sync engine can
/// branch on. Everything about WHAT to send lives in [SyncService], so the
/// transport can be swapped again without touching the sync rules.
class ApiClient {
  ApiClient({required this.token, http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String token;
  final http.Client _client;
  final String _baseUrl;

  static const _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'accept': 'application/json',
      };

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final response = await _client.get(uri, headers: _headers).timeout(_timeout);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(String path, Object body) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response =
        await _client.post(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  void close() => _client.close();

  /// Swap a pairing code for a device token. The one call made without one.
  static Future<({String token, String tenantId})?> exchangePairingCode(
    String code, {
    http.Client? client,
    String? baseUrl,
  }) async {
    final http.Client c = client ?? http.Client();
    try {
      final response = await c
          .post(
            Uri.parse('${baseUrl ?? ApiConfig.baseUrl}/api/m/devices/exchange'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'code': code}),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['token'] as String?;
      final tenantId = body['tenantId'] as String?;
      if (token == null || tenantId == null) return null;
      return (token: token, tenantId: tenantId);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
