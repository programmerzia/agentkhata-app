package no.osilion.agentkhata

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persists captured messages while the Flutter engine is not running, so
 * nothing is lost when the app is closed. Drained on app start.
 * Secrets never reach this queue: see [SecretFilter].
 */
object MessageQueue {
    private const val PREFS = "agentkhata_queue"
    private const val KEY = "pending"
    private const val MAX = 500

    @Volatile var liveSink: ((Map<String, Any?>) -> Unit)? = null

    fun push(ctx: Context, msg: Map<String, Any?>) {
        val sink = liveSink
        if (sink != null) {
            sink(msg); return
        }
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        arr.put(JSONObject(msg))
        val trimmed = if (arr.length() > MAX) JSONArray().also { for (i in arr.length() - MAX until arr.length()) it.put(arr.get(i)) } else arr
        prefs.edit().putString(KEY, trimmed.toString()).apply()
    }

    fun drain(ctx: Context): List<Map<String, Any?>> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        prefs.edit().remove(KEY).apply()
        val out = ArrayList<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(mapOf(
                "body" to o.optString("body"),
                "sender" to o.optString("sender"),
                "package" to o.optString("package", null),
                "isSms" to o.optBoolean("isSms"),
                "at" to o.optLong("at"),
            ))
        }
        return out
    }
}

/** Drops OTP / PIN / password messages at the edge so they never cross to Dart or disk. */
object SecretFilter {
    private val secret = Regex("\\b(otp|one[- ]time|verification code|pin|password|passcode)\\b", RegexOption.IGNORE_CASE)
    fun isSecret(text: String) = secret.containsMatchIn(text)
}
