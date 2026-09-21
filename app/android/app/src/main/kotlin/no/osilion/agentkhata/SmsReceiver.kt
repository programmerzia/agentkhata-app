package no.osilion.agentkhata

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Optional SMS path. Only fires when the user granted RECEIVE_SMS. Multipart
 * messages are joined before filtering so the OTP check sees the whole text.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val sender = parts[0].displayOriginatingAddress ?: ""
        val body = parts.joinToString("") { it.displayMessageBody ?: "" }
        if (body.isBlank() || SecretFilter.isSecret(body)) return
        MessageQueue.push(context.applicationContext, mapOf(
            "body" to body,
            "sender" to sender,
            "package" to null,
            "isSms" to true,
            "at" to parts[0].timestampMillis,
        ))
        MessageQueue.wake(context.applicationContext)
    }
}
