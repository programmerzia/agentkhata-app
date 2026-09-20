package no.osilion.agentkhata

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Primary capture path (no SMS permission needed). Only the operator apps
 * listed in [PACKAGES] are read; every other notification is ignored.
 */
class OperatorNotificationListener : NotificationListenerService() {
    companion object {
        val PACKAGES = setOf(
            "com.bkash.businessapp", "com.bkash.customerapp",
            "com.konasl.nagad.agent", "com.konasl.nagad",
            "com.dbbl.mbs.apps.main",
            "com.ucb.upay",
            "com.trustbank.tap",
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in PACKAGES) return
        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
        val body = if (title.isNotBlank() && !text.contains(title)) "$title. $text" else text
        if (SecretFilter.isSecret(body)) return
        MessageQueue.push(applicationContext, mapOf(
            "body" to body,
            "sender" to sbn.packageName,
            "package" to sbn.packageName,
            "isSms" to false,
            "at" to sbn.postTime,
        ))
    }
}
