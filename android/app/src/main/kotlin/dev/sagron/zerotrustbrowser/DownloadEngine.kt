package dev.sagron.zerotrustbrowser

import android.content.ContentValues
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/**
 * ZT Browser's own downloader (B34), in place of Android's download
 * manager: pause, resume where it stopped, retry by itself when the
 * connection drops, the page as Referer, and no size limit for files a page
 * makes itself. Files from private tabs (B33) are written encrypted into
 * [PrivateVault] and are never listed on disk or in Android's Downloads.
 *
 * Normal downloads are written straight into a hidden ("pending") entry in
 * the phone's Downloads, which other apps can't see until it is complete.
 * Only normal downloads are remembered across restarts, without cookies.
 */
class DownloadEngine private constructor(private val app: Context) {

    /** One download. Fields are read by other threads, hence volatile. */
    class Job(
        val key: String,
        @Volatile var name: String,
        val mime: String,
        val time: Long,
        val private: Boolean,
        /** http(s) address; null for a file the page made (blob:/data:). */
        val url: String?,
        val referer: String?,
        val userAgent: String?,
        val openWhenDone: Boolean,
    ) {
        /** queued, running, waiting (for the network), paused, done, failed. */
        @Volatile var status: String = "queued"
        @Volatile var bytes: Long = 0
        @Volatile var total: Long = -1
        @Volatile var etag: String? = null
        @Volatile var lastModified: String? = null

        /** Normal downloads: the Downloads entry (pending until done). */
        @Volatile var uri: String? = null

        /** Why it failed: network, http, space, gone (the source went away). */
        @Volatile var error: String? = null

        /** Cookies for the next request, never saved to disk. */
        @Volatile var cookie: String? = null

        /** A file the page made: read once, so it can't be paused or retried. */
        @Volatile var source: ChunkSource? = null

        @Volatile var stop: String? = null
        @Volatile var attempts = 0

        /** Goes up on every (re)start, so an older worker knows to stop. */
        @Volatile var generation = 0

        val active get() = status == "queued" || status == "running" || status == "waiting"
        val resumable get() = url != null

        fun file(context: Context) = File(PrivateVault.dir(context), "$key.ztp")

        fun toMap(): Map<String, Any?> = mapOf(
            "key" to key,
            "name" to name,
            "mime" to mime,
            "time" to time,
            "status" to status,
            "bytes" to bytes,
            "total" to total,
            "private" to private,
            "error" to error,
            "canPause" to (resumable && active),
            "canResume" to (resumable && (status == "paused" || status == "failed")),
            // B36: copy link, rename.
            "url" to url,
            "canRename" to (status == "done"),
        )

        fun toJson(): JSONObject = JSONObject()
            .put("key", key).put("name", name).put("mime", mime).put("time", time)
            .put("url", url).put("referer", referer).put("ua", userAgent)
            .put("status", status).put("bytes", bytes).put("total", total)
            .put("etag", etag).put("lastModified", lastModified).put("uri", uri).put("error", error)

        companion object {
            fun fromJson(o: JSONObject): Job = Job(
                key = o.getString("key"),
                name = o.optString("name"),
                mime = o.optString("mime", "application/octet-stream"),
                time = o.optLong("time"),
                private = false,
                url = o.optString("url").takeIf { it.isNotEmpty() && it != "null" },
                referer = o.optString("referer").takeIf { it.isNotEmpty() && it != "null" },
                userAgent = o.optString("ua").takeIf { it.isNotEmpty() && it != "null" },
                openWhenDone = false,
            ).apply {
                status = o.optString("status", "failed")
                bytes = o.optLong("bytes")
                total = o.optLong("total", -1)
                etag = o.optString("etag").takeIf { it.isNotEmpty() && it != "null" }
                lastModified = o.optString("lastModified").takeIf { it.isNotEmpty() && it != "null" }
                uri = o.optString("uri").takeIf { it.isNotEmpty() && it != "null" }
                error = o.optString("error").takeIf { it.isNotEmpty() && it != "null" }
            }
        }
    }

    /** The bytes of a file the page made, pulled a piece at a time. */
    interface ChunkSource {
        /** The next piece, or null at the end; throws when it went wrong. */
        fun next(): ByteArray?
        fun cancel()
    }

    /** Something about the downloads changed (progress too, at most twice a second). */
    val onChanged = CopyOnWriteArraySet<() -> Unit>()

    /** A download finished: done or failed. */
    val onFinished = CopyOnWriteArraySet<(Job) -> Unit>()

    /** Texts in the app's language, pushed from Dart (`downloadLabels`). */
    @Volatile var labels: Map<String, String> = emptyMap()

    fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback

    private val jobs = ConcurrentHashMap<String, Job>()

    /** Jobs wait for a free slot (B38: how many at once) inside [run]. */
    private val workers = Executors.newCachedThreadPool()
    private val slots = Object()
    private var runningCount = 0
    private val prefs = app.getSharedPreferences("zt_download_jobs", Context.MODE_PRIVATE)

    /** B37: the list, encrypted on this phone (it used to be in [prefs]). */
    private val store = EncryptedStore(app, "download-jobs")

    // ---- B38: download rules ----

    /** Only download over Wi-Fi (or any network that isn't metered). */
    @Volatile var wifiOnly = false

    /** How many downloads run at once. */
    @Volatile var maxParallel = DEFAULT_PARALLEL
        set(value) {
            field = value.coerceIn(1, 6)
            synchronized(slots) { slots.notifyAll() }
        }

    /** Finished downloads older than this many days are deleted; 0 never. */
    @Volatile var autoDeleteDays = 0

    /** A folder the person picked (a tree from the Files app), or null for Downloads. */
    @Volatile var folder: Uri? = prefs.getString("folder", null)?.let(Uri::parse)
        private set

    fun setFolder(tree: Uri?) {
        folder = tree
        prefs.edit().apply { if (tree == null) remove("folder") else putString("folder", tree.toString()) }.apply()
    }
    private val main = Handler(Looper.getMainLooper())
    private val wake = Object()
    @Volatile private var lastTick = 0L

    init {
        // A new process: the old private key is gone, and so are its files.
        PrivateVault.wipe(app)
        // B37: the encrypted list; once, the old plain one moves into it.
        val old = prefs.getString("jobs", null)
        val raw = store.read() ?: old ?: "[]"
        val arr = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
        for (i in 0 until arr.length()) {
            val job = try { Job.fromJson(arr.getJSONObject(i)) } catch (e: Exception) { continue }
            // The app was closed mid-download: resume when asked.
            if (job.status == "queued" || job.status == "running" || job.status == "waiting") {
                job.status = if (job.resumable) "paused" else "failed"
                if (!job.resumable) job.error = "gone"
            }
            jobs[job.key] = job
        }
        if (old != null) {
            save()
            prefs.edit().remove("jobs").apply()
        }
        try {
            app.getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) = poke()
                    override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = poke()
                },
            )
        } catch (e: Exception) {
            // Without it, waiting downloads retry on their timer.
        }
        onFinished.add { DownloadService.finished(app, it) }
    }

    private fun poke() = synchronized(wake) { wake.notifyAll() }

    fun job(key: String): Job? = jobs[key]

    /** Newest first. */
    fun list(): List<Job> = jobs.values.sortedByDescending { it.time }

    fun anyActive(): Boolean = jobs.values.any { it.active }

    private fun save() {
        val arr = JSONArray()
        jobs.values.filter { !it.private }.sortedBy { it.time }.takeLast(KEEP).forEach { arr.put(it.toJson()) }
        store.write(arr.toString())
    }

    private fun changed(force: Boolean = true) {
        val now = System.currentTimeMillis()
        if (!force && now - lastTick < 500) return
        lastTick = now
        main.post { onChanged.forEach { it() } }
    }

    private fun setStatus(job: Job, status: String) {
        job.status = status
        if (!job.private) save()
        changed()
        if (status == "done" || status == "failed") main.post { onFinished.forEach { it(job) } }
    }

    /** Starts downloading a web address. */
    fun startHttp(
        url: String,
        name: String,
        mime: String,
        private: Boolean,
        cookie: String?,
        referer: String?,
        userAgent: String?,
        totalHint: Long,
        openWhenDone: Boolean,
    ): Job {
        val job = Job(
            key = UUID.randomUUID().toString(),
            name = cleanName(name),
            mime = mime,
            time = System.currentTimeMillis(),
            private = private,
            url = url,
            referer = referer,
            userAgent = userAgent,
            openWhenDone = openWhenDone,
        )
        job.cookie = cookie
        job.total = totalHint
        jobs[job.key] = job
        enqueue(job)
        return job
    }

    /** Starts saving a file the page made, read from [source]. */
    fun startInline(name: String, mime: String, private: Boolean, source: ChunkSource, openWhenDone: Boolean, totalHint: Long): Job {
        val job = Job(
            key = UUID.randomUUID().toString(),
            name = cleanName(name),
            mime = mime,
            time = System.currentTimeMillis(),
            private = private,
            url = null,
            referer = null,
            userAgent = null,
            openWhenDone = openWhenDone,
        )
        job.source = source
        job.total = totalHint
        jobs[job.key] = job
        enqueue(job)
        return job
    }

    private fun enqueue(job: Job) {
        job.stop = null
        job.error = null
        job.attempts = 0
        setStatus(job, "queued")
        val generation = ++job.generation
        DownloadService.start(app)
        workers.execute { run(job, generation) }
    }

    fun pause(key: String) {
        val job = jobs[key] ?: return
        if (!job.resumable || !job.active) return
        job.stop = "pause"
        poke()
        // Not started yet: it never will be.
        if (job.status == "queued") setStatus(job, "paused")
    }

    /** Resumes a paused download, or tries a failed one again. */
    fun resume(key: String, cookie: String?) {
        val job = jobs[key] ?: return
        if (!job.resumable || job.active || job.status == "done") return
        if (cookie != null) job.cookie = cookie
        enqueue(job)
    }

    /** Stops a download and deletes what it saved. */
    fun delete(key: String) {
        val job = jobs.remove(key) ?: return
        job.stop = "cancel"
        job.source?.cancel()
        poke()
        discard(job)
        if (!job.private) save()
        changed()
    }

    private fun discard(job: Job) {
        if (job.private) {
            job.file(app).delete()
        } else {
            job.uri?.let { u -> deleteEntry(Uri.parse(u)) }
        }
    }

    /**
     * B36: takes finished or failed downloads off the list; their files stay
     * where they are. A private one has no other place, so it is deleted.
     */
    fun forget(keys: Collection<String>) {
        for (key in keys) {
            val job = jobs[key] ?: continue
            if (job.active) continue
            jobs.remove(key)
            if (job.private) discard(job)
        }
        save()
        changed()
    }

    /** B36: a finished download gets a new name; false when it can't. */
    fun rename(key: String, newName: String): Boolean {
        val job = jobs[key] ?: return false
        if (job.status != "done") return false
        val name = cleanName(newName)
        if (name == job.name) return true
        if (!job.private) {
            val uri = job.uri?.let(Uri::parse) ?: return false
            try {
                if (DocumentsContract.isDocumentUri(app, uri)) {
                    val renamed = DocumentsContract.renameDocument(app.contentResolver, uri, name) ?: return false
                    job.uri = renamed.toString()
                } else {
                    val values = ContentValues().apply { put(MediaStore.Downloads.DISPLAY_NAME, name) }
                    if (app.contentResolver.update(uri, values, null, null) <= 0) return false
                }
            } catch (e: Exception) {
                return false
            }
            job.name = displayName(Uri.parse(job.uri)) ?: name
        } else {
            job.name = name
            // A plain copy made for another app keeps the old name: redo it.
            File(PrivateVault.openDir(app), job.key).deleteRecursively()
        }
        save()
        changed()
        return true
    }

    /** B38: deletes finished downloads older than [autoDeleteDays]. */
    fun deleteOld(now: Long = System.currentTimeMillis()) {
        val days = autoDeleteDays
        if (days <= 0) return
        val before = now - days * 86_400_000L
        val old = jobs.values.filter { !it.private && it.status == "done" && it.time < before }
        if (old.isEmpty()) return
        for (job in old) {
            jobs.remove(job.key)
            discard(job)
        }
        save()
        changed()
    }

    /** The private session ended: every private download is gone for good. */
    fun endPrivateSession() {
        for (job in jobs.values.filter { it.private }) {
            jobs.remove(job.key)
            job.stop = "cancel"
            job.source?.cancel()
        }
        poke()
        PrivateVault.wipe(app)
        DownloadService.clearPrivate(app)
        changed()
    }

    fun hasPrivate(): Boolean = jobs.values.any { it.private }

    /**
     * Moves a finished private download out of the vault into the phone's
     * Downloads: it then stays after the private session, like any download.
     */
    fun saveToPhone(key: String): Boolean {
        val job = jobs[key] ?: return false
        if (!job.private || job.status != "done") return false
        val uri = newEntry(job.name, job.mime) ?: return false
        try {
            app.contentResolver.openOutputStream(uri)?.use { out ->
                PrivateVault.reader(job.file(app)).use { it.copyTo(out, BUFFER) }
            } ?: throw IOException("no stream")
            publish(uri)
        } catch (e: Exception) {
            try { app.contentResolver.delete(uri, null, null) } catch (ex: Exception) { }
            return false
        }
        job.file(app).delete()
        val saved = Job(job.key, job.name, job.mime, job.time, false, null, null, null, false).apply {
            status = "done"
            bytes = job.bytes
            total = job.bytes
            this.uri = uri.toString()
        }
        jobs[key] = saved
        save()
        changed()
        return true
    }

    /**
     * B39: the plain bytes of a finished download (a private one decrypted),
     * to move it into the vault; null when it isn't there.
     */
    fun openInput(key: String): InputStream? {
        val job = jobs[key] ?: return null
        if (job.status != "done") return null
        return try {
            if (job.private) {
                PrivateVault.reader(job.file(app))
            } else {
                job.uri?.let { app.contentResolver.openInputStream(Uri.parse(it)) }
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * B39: a file taken out of the vault, saved into Downloads (or the
     * picked folder) and listed like any finished download.
     */
    fun saveFromVault(name: String, mime: String, size: Long, write: (OutputStream) -> Unit): Boolean {
        val uri = newEntry(name, mime) ?: return false
        try {
            app.contentResolver.openOutputStream(uri)?.use(write) ?: throw IOException("no stream")
            publish(uri)
        } catch (e: Exception) {
            deleteEntry(uri)
            return false
        }
        val job = Job(UUID.randomUUID().toString(), displayName(uri) ?: name, mime, System.currentTimeMillis(), false, null, null, null, false).apply {
            status = "done"
            bytes = size
            total = size
            this.uri = uri.toString()
        }
        jobs[job.key] = job
        save()
        changed()
        return true
    }

    /**
     * A plain copy of a private download for another app to open, deleted
     * when the private session ends; null when it can't be made.
     */
    fun privateCopy(key: String): File? {
        val job = jobs[key] ?: return null
        if (!job.private || job.status != "done") return null
        val dir = File(PrivateVault.openDir(app), job.key).apply { mkdirs() }
        val out = File(dir, job.name)
        if (out.exists() && out.length() == job.bytes) return out
        return try {
            FileOutputStream(out).use { o -> PrivateVault.reader(job.file(app)).use { it.copyTo(o, BUFFER) } }
            out
        } catch (e: Exception) {
            out.delete()
            null
        }
    }

    // ---- The work, on a worker thread --------------------------------------

    private class Stopped : Exception()
    private class Fatal(val reason: String) : Exception(reason)

    /** Which start of a job this worker thread is running. */
    private val runningGeneration = ThreadLocal<Int>()

    /**
     * Paused (or cancelled), or started again since this worker began
     * (pause then resume in quick succession): this worker must stop.
     */
    private fun stale(job: Job) = job.stop != null || job.generation != runningGeneration.get()

    private fun run(job: Job, generation: Int) {
        // One worker per job at a time: a newer start waits for the older
        // one to notice it is stale and let go.
        synchronized(job) {
            runningGeneration.set(generation)
            try {
                // B38: wait for a free slot; a job paused meanwhile gives up.
                synchronized(slots) {
                    while (runningCount >= maxParallel && !stale(job)) slots.wait(1_000)
                    if (stale(job)) {
                        stopped(job)
                        return
                    }
                    runningCount++
                }
                try {
                    runLocked(job)
                } finally {
                    synchronized(slots) {
                        runningCount--
                        slots.notifyAll()
                    }
                }
            } finally {
                runningGeneration.remove()
            }
        }
    }

    /** Stopped by the person: say so, unless a newer start took over. */
    private fun stopped(job: Job) {
        if (job.stop == "pause" && job.generation == runningGeneration.get()) setStatus(job, "paused")
    }

    private fun runLocked(job: Job) {
        if (stale(job) || jobs[job.key] !== job) {
            stopped(job)
            return
        }
        setStatus(job, "running")
        while (true) {
            // B38: Wi-Fi only waits for Wi-Fi (a file the page made is
            // already on the phone).
            if (job.url != null && wifiOnly && !unmetered()) {
                job.error = "wifi"
                setStatus(job, "waiting")
                synchronized(wake) {
                    if (!stale(job)) wake.wait(30_000)
                }
                if (stale(job)) {
                    stopped(job)
                    return
                }
                continue
            }
            if (job.error == "wifi") {
                job.error = null
                setStatus(job, "running")
            }
            try {
                if (job.url != null) transferHttp(job) else transferInline(job)
                setStatus(job, "done")
                return
            } catch (e: Stopped) {
                stopped(job)
                return
            } catch (e: Fatal) {
                job.error = e.reason
                setStatus(job, "failed")
                return
            } catch (e: Exception) {
                if (stale(job)) {
                    stopped(job)
                    return
                }
                if (!job.resumable) {
                    job.error = if (e is IOException && e.message == "space") "space" else "gone"
                    setStatus(job, "failed")
                    return
                }
                job.error = if (e.message == "space") "space" else "network"
                if (job.error == "space") {
                    setStatus(job, "failed")
                    return
                }
                // The connection dropped: wait, then go on where it stopped.
                if (online()) job.attempts++
                if (job.attempts > MAX_ATTEMPTS) {
                    setStatus(job, "failed")
                    return
                }
                setStatus(job, "waiting")
                val delay = minOf(60_000L, 2_000L shl minOf(job.attempts, 5))
                synchronized(wake) {
                    if (!stale(job)) wake.wait(delay)
                }
                if (stale(job)) {
                    stopped(job)
                    return
                }
                setStatus(job, "running")
            }
        }
    }

    private fun unmetered(): Boolean = try {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
        caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    } catch (e: Exception) {
        true
    }

    private fun online(): Boolean = try {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        cm?.activeNetwork != null
    } catch (e: Exception) {
        true
    }

    private fun checkStop(job: Job) {
        if (stale(job)) throw Stopped()
    }

    /** One try at downloading the rest of [job]. */
    private fun transferHttp(job: Job) {
        // Without a validator the server can't tell us the file changed, and
        // resuming could glue two different files together: start over.
        if (job.etag == null && job.lastModified == null) return transferFresh(job)
        val (start, sink) = openSink(job, resume = true)
        var conn: HttpURLConnection? = null
        var finished = false
        try {
            conn = connect(job, start)
            val code = conn.responseCode
            val from = start
            when {
                code == 416 && start > 0 && job.total > 0 && start >= job.total -> {
                    // Everything was already here.
                    job.bytes = start
                    sink.finish()
                    finished = true
                    return
                }
                code == 206 && start > 0 -> Unit
                code in 200..299 -> {
                    // The server sent the whole file (no resume): start over.
                    if (start > 0) {
                        sink.close()
                        conn.disconnect()
                        return transferFresh(job)
                    }
                }
                code == 408 || code == 429 || code >= 500 -> throw IOException("http $code")
                else -> throw Fatal("http")
            }
            job.etag = conn.getHeaderField("ETag") ?: job.etag
            job.lastModified = conn.getHeaderField("Last-Modified") ?: job.lastModified
            job.total = totalOf(conn, from)
            // Kept before any byte is written, so a resume after a crash can check them.
            if (!job.private) save()
            copy(job, conn.inputStream, sink.stream, from)
            sink.finish()
            finished = true
        } finally {
            if (!finished) sink.close()
            conn?.disconnect()
        }
    }

    /** The server can't resume: throw away what we have and download it all. */
    private fun transferFresh(job: Job) {
        val (_, sink) = openSink(job, resume = false)
        var finished = false
        var conn: HttpURLConnection? = null
        try {
            conn = connect(job, 0)
            val code = conn.responseCode
            if (code == 408 || code == 429 || code >= 500) throw IOException("http $code")
            if (code !in 200..299) throw Fatal("http")
            job.etag = conn.getHeaderField("ETag")
            job.lastModified = conn.getHeaderField("Last-Modified")
            job.total = totalOf(conn, 0)
            if (!job.private) save()
            copy(job, conn.inputStream, sink.stream, 0)
            sink.finish()
            finished = true
        } finally {
            if (!finished) sink.close()
            conn?.disconnect()
        }
    }

    @Suppress("DEPRECATION") // URL(String): addresses from the page are already encoded.
    private fun connect(job: Job, start: Long): HttpURLConnection {
        val conn = URL(job.url).openConnection() as HttpURLConnection
        conn.connectTimeout = 30_000
        conn.readTimeout = 60_000
        conn.instanceFollowRedirects = true
        job.userAgent?.let { conn.setRequestProperty("User-Agent", it) }
        job.referer?.let { conn.setRequestProperty("Referer", it) }
        job.cookie?.let { conn.setRequestProperty("Cookie", it) }
        // The real bytes, so sizes and resuming line up.
        conn.setRequestProperty("Accept-Encoding", "identity")
        if (start > 0) {
            conn.setRequestProperty("Range", "bytes=$start-")
            (job.etag ?: job.lastModified)?.let { conn.setRequestProperty("If-Range", it) }
        }
        return conn
    }

    private fun totalOf(conn: HttpURLConnection, from: Long): Long {
        conn.getHeaderField("Content-Range")?.substringAfter('/')?.trim()?.toLongOrNull()?.let { return it }
        val len = conn.getHeaderField("Content-Length")?.trim()?.toLongOrNull() ?: return -1
        return from + len
    }

    private fun copy(job: Job, input: InputStream, out: OutputStream, from: Long) {
        val buf = ByteArray(BUFFER)
        var done = from
        job.bytes = done
        input.use {
            while (true) {
                checkStop(job)
                val n = it.read(buf)
                if (n < 0) break
                write(out, buf, n)
                done += n
                job.bytes = done
                if (job.attempts > 0 && done - from > BUFFER * 16) job.attempts = 0
                changed(force = false)
            }
        }
        if (job.total > 0 && done < job.total) throw IOException("short")
        if (job.total <= 0) job.total = done
    }

    private fun write(out: OutputStream, buf: ByteArray, n: Int) {
        try {
            out.write(buf, 0, n)
        } catch (e: IOException) {
            if (e.message?.contains("ENOSPC") == true || e.message?.contains("No space") == true) throw IOException("space")
            throw e
        }
    }

    private fun transferInline(job: Job) {
        val source = job.source ?: throw Fatal("gone")
        val (_, sink) = openSink(job, resume = false)
        var finished = false
        try {
            var done = 0L
            while (true) {
                checkStop(job)
                val piece = source.next() ?: break
                write(sink.stream, piece, piece.size)
                done += piece.size
                job.bytes = done
                changed(force = false)
            }
            job.total = done
            sink.finish()
            finished = true
        } finally {
            job.source = null
            if (!finished) {
                sink.close()
                source.cancel()
            }
        }
    }

    // ---- Where the bytes go -----------------------------------------------

    /** Where a download is written, and how much of it is already there. */
    private class Sink(val stream: OutputStream, val onFinish: () -> Unit, val onClose: () -> Unit) {
        fun finish() {
            stream.flush()
            onFinish()
        }

        fun close() = onClose()
    }

    private fun openSink(job: Job, resume: Boolean): Pair<Long, Sink> {
        if (job.private) {
            val file = job.file(app)
            val start = if (resume) PrivateVault.committedLength(file) else 0L
            val w = PrivateVault.Writer(file, resume = resume && start > 0)
            return start to Sink(w, { w.finish() }, { try { w.close() } catch (e: Exception) { } })
        }
        val resolver = app.contentResolver
        var uri = job.uri?.let(Uri::parse)
        val pfd = uri?.let { u ->
            try { resolver.openFileDescriptor(u, "rw") } catch (e: Exception) { null }
        } ?: run {
            // Never started, or the half-done file was cleared: start afresh.
            uri?.let { u -> deleteEntry(u) }
            val created = newEntry(job.name, job.mime) ?: throw Fatal("space")
            uri = created
            job.uri = created.toString()
            // The name Android gave it ("report (1).pdf" when taken).
            displayName(created)?.let { job.name = it }
            save()
            resolver.openFileDescriptor(created, "rw") ?: throw Fatal("space")
        }
        val stream = FileOutputStream(pfd.fileDescriptor)
        val channel = stream.channel
        val start = if (resume) channel.size() else 0L
        if (!resume) channel.truncate(0)
        channel.position(start)
        val finalUri = uri!!
        return start to Sink(
            stream,
            {
                stream.fd.sync()
                stream.close()
                pfd.close()
                publish(finalUri)
            },
            {
                try { stream.close() } catch (e: Exception) { }
                try { pfd.close() } catch (e: Exception) { }
            },
        )
    }

    /**
     * A new file in the folder the person picked (B38), or else a hidden
     * entry in the phone's Downloads, shown once [publish]ed.
     */
    private fun newEntry(name: String, mime: String): Uri? {
        folder?.let { tree ->
            try {
                val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                DocumentsContract.createDocument(app.contentResolver, parent, mime, name)?.let { return it }
            } catch (e: Exception) {
                // The folder is gone or no longer allowed: use Downloads.
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        return try {
            app.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        } catch (e: Exception) {
            null
        }
    }

    private fun publish(uri: Uri) {
        if (DocumentsContract.isDocumentUri(app, uri)) return // A picked folder: already visible.
        val values = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
        app.contentResolver.update(uri, values, null, null)
    }

    /** Deletes a file in Downloads or in a picked folder. */
    private fun deleteEntry(uri: Uri) {
        try {
            if (DocumentsContract.isDocumentUri(app, uri)) {
                DocumentsContract.deleteDocument(app.contentResolver, uri)
            } else {
                app.contentResolver.delete(uri, null, null)
            }
        } catch (e: Exception) {
            // Already gone.
        }
    }

    private fun displayName(uri: Uri): String? = try {
        app.contentResolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.takeIf { it.isNotBlank() } else null
        }
    } catch (e: Exception) {
        null
    }

    companion object {
        private const val DEFAULT_PARALLEL = 3
        private const val MAX_ATTEMPTS = 8
        private const val BUFFER = 64 * 1024
        private const val KEEP = 200

        @Volatile private var instance: DownloadEngine? = null

        fun get(context: Context): DownloadEngine =
            instance ?: synchronized(this) {
                instance ?: DownloadEngine(context.applicationContext).also { instance = it }
            }

        /**
         * A file name that is only a name: no folders, no invisible or
         * direction-changing characters that can disguise "exe.pdf" as
         * "pdf.exe", not empty, not too long.
         */
        fun cleanName(raw: String): String {
            val cleaned = raw
                .replace(Regex("[\\u0000-\\u001f\\u007f\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]"), "")
                .replace(Regex("[/\\\\:*?\"<>|]"), "_")
                .trim()
                .trimStart('.')
                .trim()
            val name = cleaned.ifEmpty { "download" }
            if (name.length <= 120) return name
            val dot = name.lastIndexOf('.')
            val ext = if (dot > 0 && name.length - dot <= 10) name.substring(dot) else ""
            return name.substring(0, 120 - ext.length) + ext
        }
    }
}
