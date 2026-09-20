import 'dart:async';

import 'package:flutter/services.dart';

/// Bridge to the Kotlin side (NotificationListenerService + SMS receiver).
class IncomingMessage {
  const IncomingMessage({required this.body, required this.sender, this.packageName, required this.isSms, required this.receivedAt});
  final String body;
  final String sender;
  final String? packageName;
  final bool isSms;
  final DateTime receivedAt;
}

class MessageChannel {
  static const _events = EventChannel('no.osilion.agentkhata/messages');
  static const _methods = MethodChannel('no.osilion.agentkhata/control');

  static Stream<IncomingMessage> stream() => _events.receiveBroadcastStream().map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return IncomingMessage(
          body: m['body'] as String? ?? '',
          sender: m['sender'] as String? ?? '',
          packageName: m['package'] as String?,
          isSms: m['isSms'] as bool? ?? false,
          receivedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
        );
      });

  static Future<bool> isNotificationAccessGranted() async => (await _methods.invokeMethod<bool>('isNotificationAccessGranted')) ?? false;
  static Future<void> openNotificationAccessSettings() => _methods.invokeMethod('openNotificationAccessSettings');

  /// Messages captured while the Flutter engine was not running are queued
  /// natively and drained on start.
  static Future<List<IncomingMessage>> drainQueue() async {
    final list = await _methods.invokeMethod<List<dynamic>>('drainQueue') ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return IncomingMessage(
        body: m['body'] as String? ?? '',
        sender: m['sender'] as String? ?? '',
        packageName: m['package'] as String?,
        isSms: m['isSms'] as bool? ?? false,
        receivedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }
}
