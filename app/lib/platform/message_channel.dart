import 'dart:async';

import 'package:flutter/services.dart';

/// One operator message, as the native queue holds it until Dart is done.
class QueuedMessage {
  const QueuedMessage({
    required this.id,
    required this.body,
    required this.sender,
    this.packageName,
    required this.isSms,
    required this.receivedAt,
  });

  /// The queue's own id. Acknowledged back once the message is in the books.
  final String id;
  final String body;
  final String sender;
  final String? packageName;
  final bool isSms;
  final DateTime receivedAt;
}

/// What the phone can say about its own ability to capture.
///
/// Every field is a way capture silently stops on a real phone in a real
/// shop, which is why all of it travels to the portal: the owner sees "the
/// Rocket phone lost notification access on Tuesday" instead of discovering a
/// day close that does not balance.
class PhoneHealth {
  const PhoneHealth({
    required this.notificationAccess,
    required this.smsAccess,
    required this.batteryUnrestricted,
    required this.queued,
    this.lastCaptureAt,
    this.manufacturer,
  });

  final bool notificationAccess;
  final bool smsAccess;
  final bool batteryUnrestricted;
  final int queued;
  final DateTime? lastCaptureAt;
  final String? manufacturer;

  /// Capture works if at least one door is open, and the phone will not kill it.
  bool get capturing => (notificationAccess || smsAccess) && batteryUnrestricted;

  Map<String, dynamic> toJson() => {
        'notificationAccess': notificationAccess,
        'smsAccess': smsAccess,
        'batteryUnrestricted': batteryUnrestricted,
        'queued': queued,
      };
}

class PhoneIdentity {
  const PhoneIdentity({required this.model, required this.appVersion});
  final String model;
  final String appVersion;
}

/// Bridge to the Kotlin side: the notification listener, the SMS receiver,
/// the durable queue between them and Dart, and the phone's health.
///
/// Every call degrades to a safe answer when there is no native side — unit
/// tests and desktop runs — so the code that uses it needs no platform checks.
class MessageChannel {
  static const _events = EventChannel('no.osilion.agentkhata/messages');
  static const _methods = MethodChannel('no.osilion.agentkhata/control');

  /// Fires when a message has been queued and this (UI) engine should process.
  static Stream<void> wakes() => _events.receiveBroadcastStream().map((_) {});

  static Future<bool> isNotificationAccessGranted() async =>
      (await _call<bool>('isNotificationAccessGranted')) ?? false;

  static Future<void> openNotificationAccessSettings() => _call<void>('openNotificationAccessSettings');

  static Future<List<QueuedMessage>> peekQueue() async {
    final list = await _call<List<dynamic>>('peekQueue') ?? const [];
    return [
      for (final raw in list)
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          return QueuedMessage(
            id: m['id'] as String,
            body: m['body'] as String? ?? '',
            sender: m['sender'] as String? ?? '',
            packageName: m['package'] as String?,
            isSms: m['isSms'] as bool? ?? false,
            receivedAt: DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0),
          );
        }(),
    ];
  }

  static Future<void> ackQueue(List<String> ids) async {
    if (ids.isEmpty) return;
    await _call<void>('ackQueue', {'ids': ids});
  }

  /// A lease shared by every engine in this process. See EngineLock.kt.
  ///
  /// With no native side there is only one engine, so the answer is yes.
  static Future<bool> tryLock(String name, Duration lease) async =>
      (await _call<bool>('tryLock', {'name': name, 'leaseMs': lease.inMilliseconds})) ?? true;

  static Future<void> unlock(String name) => _call<void>('unlock', {'name': name});

  static Future<PhoneHealth?> health() async {
    final raw = await _call<Map<dynamic, dynamic>>('health');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw);
    final last = (m['lastCaptureAt'] as num?)?.toInt();
    return PhoneHealth(
      notificationAccess: m['notificationAccess'] as bool? ?? false,
      smsAccess: m['smsAccess'] as bool? ?? false,
      batteryUnrestricted: m['batteryUnrestricted'] as bool? ?? false,
      queued: (m['queued'] as num?)?.toInt() ?? 0,
      lastCaptureAt: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      manufacturer: m['manufacturer'] as String?,
    );
  }

  static Future<PhoneIdentity?> identity() async {
    final raw = await _call<Map<dynamic, dynamic>>('device');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw);
    return PhoneIdentity(model: m['model'] as String? ?? 'Android', appVersion: m['appVersion'] as String? ?? '?');
  }

  /// Package names of the operator apps installed on this phone.
  static Future<List<String>> installedOperatorApps() async =>
      ((await _call<List<dynamic>>('installedOperatorApps')) ?? const []).cast<String>();

  static Future<bool> requestBatteryUnrestricted() async =>
      (await _call<bool>('requestBatteryUnrestricted')) ?? false;

  /// False when this phone has no manufacturer autostart screen at all.
  static Future<bool> openAutostartSettings() async => (await _call<bool>('openAutostartSettings')) ?? false;

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}
