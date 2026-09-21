package no.osilion.agentkhata

import android.os.SystemClock

/**
 * One engine at a time, per job.
 *
 * The UI engine and the background engine can both be alive for a moment —
 * the app opens while the background engine is still finishing a sync. Both
 * processing the queue would ingest a message twice; both syncing would push
 * the same rows twice. They share this process, so a lock in native memory is
 * visible to both, which no Dart-side lock is.
 *
 * Leases rather than plain locks: an engine destroyed mid-job never releases,
 * and a lease that expires is the difference between "that job was lost" and
 * "sync never runs again on this phone".
 */
object EngineLock {
    private val expiries = HashMap<String, Long>()

    @Synchronized
    fun tryAcquire(name: String, leaseMs: Long): Boolean {
        val now = SystemClock.elapsedRealtime()
        val held = expiries[name]
        if (held != null && held > now) return false
        expiries[name] = now + leaseMs
        return true
    }

    @Synchronized
    fun release(name: String) {
        expiries.remove(name)
    }
}
