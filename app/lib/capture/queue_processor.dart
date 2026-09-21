import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/core.dart' as core;
import '../data/ingestion_service.dart';
import '../platform/message_channel.dart';

/// Move every queued operator message into the books, then off the queue.
///
/// The one path for capture, used by the UI engine and the background engine
/// alike, so a message is parsed by the same code whether the app was open or
/// not.
///
/// ## Acknowledge after, never before
///
/// A message leaves the native queue only once it is in the database — as an
/// entry, in Unsorted, or recorded as a failure. A crash half-way through
/// leaves the rest on disk for the next run. Processing the same message twice
/// after such a crash is harmless: the de-duplicator recognises the TrxID.
///
/// ## One engine at a time
///
/// Both engines can be awake for a moment. The native lease stops them
/// processing the same queue concurrently; the loser simply returns, because
/// the winner will get to its messages.
Future<int> processCaptureQueue(IngestionService ingest) async {
  if (!await MessageChannel.tryLock('process', const Duration(seconds: 45))) return 0;

  var processed = 0;
  try {
    // Messages can arrive while this runs; keep going until the queue is
    // empty, with a bound so a phone receiving faster than it parses cannot
    // hold the lease forever.
    for (var round = 0; round < 10; round++) {
      final pending = await MessageChannel.peekQueue();
      if (pending.isEmpty) break;

      final done = <String>[];
      for (final message in pending) {
        try {
          await ingest.ingest(
            body: message.body,
            sender: message.sender,
            packageName: message.packageName,
            source: message.isSms ? core.TxSource.autoSms : core.TxSource.autoNotification,
            receivedAt: message.receivedAt,
          );
        } catch (error, stack) {
          debugPrint('capture: ingest failed: $error\n$stack');
          // Kept in Unsorted rather than retried forever: a message that
          // crashes the parser will crash it the same way next time, and a
          // stuck head blocks every message behind it.
          await ingest.recordFailure(
            body: message.body,
            sender: message.sender,
            packageName: message.packageName,
            isSms: message.isSms,
            receivedAt: message.receivedAt,
            error: error,
          );
        }
        done.add(message.id);
      }
      await MessageChannel.ackQueue(done);
      processed += done.length;
    }
  } finally {
    await MessageChannel.unlock('process');
  }

  // A message queued between the last read and the unlock would have had its
  // wake-up refused by the lease. Look once more rather than leave it waiting
  // for the next capture.
  if ((await MessageChannel.peekQueue()).isNotEmpty) {
    scheduleMicrotask(() => processCaptureQueue(ingest));
  }
  return processed;
}
