package no.osilion.agentkhata

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Every captured operator message, on disk, until Dart says it is in the books.
 *
 * ## Durable first, always
 *
 * A message is written here BEFORE anyone is told about it, whether or not the
 * app is open. The earlier design handed a live message straight to the UI
 * engine and only queued it when nothing was listening, and its drain removed
 * the whole queue before Dart had processed a single entry — so a crash
 * mid-ingest, or an engine torn down at the wrong moment, lost real money
 * movements without trace.
 *
 * Now the queue is the only path: [push] persists, then wakes whichever engine
 * can process; Dart reads with [peek] and removes only what it finished with
 * [ack]. A message is in the queue or in the books, never neither.
 *
 * Secrets never reach this queue: see [SecretFilter].
 */
object MessageQueue {
    private const val PREFS = "agentkhata_queue"
    private const val KEY = "pending"

    /**
     * Enough for a busy counter's whole day with the app closed. Past this the
     * oldest go first — a queue this long means capture has been broken for
     * days, which the portal reports long before it matters.
     */
    private const val MAX = 2000

    /** Set while the UI engine is listening; a wake-up rather than a delivery. */
    @Volatile var uiWake: (() -> Unit)? = null

    @Synchronized
    fun push(ctx: Context, msg: Map<String, Any?>) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        val entry = JSONObject(msg)
        entry.put("id", UUID.randomUUID().toString())
        arr.put(entry)
        val trimmed = if (arr.length() > MAX) {
            JSONArray().also { for (i in arr.length() - MAX until arr.length()) it.put(arr.get(i)) }
        } else arr
        // commit(), not apply(): the process may be killed the moment this
        // receiver returns, and an asynchronous write would die with it.
        prefs.edit().putString(KEY, trimmed.toString()).commit()
        prefs.edit().putLong("last_capture_at", (msg["at"] as? Long) ?: System.currentTimeMillis()).commit()
    }

    /** Wake the engine that will process the queue: the UI if it is up, else a background one. */
    fun wake(ctx: Context) {
        val ui = uiWake
        if (ui != null) ui() else BackgroundEngine.kick(ctx)
    }

    @Synchronized
    fun peek(ctx: Context): List<Map<String, Any?>> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        val out = ArrayList<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(mapOf(
                "id" to o.optString("id", UUID.randomUUID().toString()),
                "body" to o.optString("body"),
                "sender" to o.optString("sender"),
                "package" to if (o.isNull("package")) null else o.optString("package"),
                "isSms" to o.optBoolean("isSms"),
                "at" to o.optLong("at"),
            ))
        }
        return out
    }

    /** Remove exactly the messages Dart finished with; anything newer stays. */
    @Synchronized
    fun ack(ctx: Context, ids: Collection<String>) {
        if (ids.isEmpty()) return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        val keep = JSONArray()
        val done = ids.toHashSet()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.optString("id") !in done) keep.put(o)
        }
        prefs.edit().putString(KEY, keep.toString()).commit()
    }

    @Synchronized
    fun size(ctx: Context): Int =
        JSONArray(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "[]")).length()

    fun lastCaptureAt(ctx: Context): Long =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("last_capture_at", 0L)
}

/** Drops OTP / PIN / password messages at the edge so they never cross to Dart or disk. */
object SecretFilter {
    private val secret = Regex("\\b(otp|one[- ]time|verification code|pin|password|passcode)\\b", RegexOption.IGNORE_CASE)
    fun isSecret(text: String) = secret.containsMatchIn(text)
}
