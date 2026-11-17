package dev.sagron.zerotrustbrowser

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.BaseColumns
import android.provider.MediaStore
import android.util.Base64
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject

/**
 * The files ZT Browser downloaded, for the Downloads page: everything from
 * [DownloadEngine] (B34), private downloads (B33) included, and the ones
 * from before it (through the system download manager, or written straight
 * to Downloads), which are only listed, opened, shared and deleted. The
 * list (names, not contents) stays on this phone.
 */
class Downloads(private val context: Context, private val engine: DownloadEngine) {
    private val prefs = context.getSharedPreferences("zt_downloads", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(DownloadManager::class.java)

    private fun entries(): MutableList<JSONObject> {
        val raw = prefs.getString("list", "[]") ?: "[]"
        val arr = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
        return MutableList(arr.length()) { arr.getJSONObject(it) }
    }

    private fun store(list: List<JSONObject>) {
        // The newest 200 are plenty for a phone browser.
        val kept = list.takeLast(200)
        prefs.edit().putString("list", JSONArray(kept).toString()).apply()
    }

    /** Newest first, with progress; files deleted elsewhere drop out. */
    @Synchronized
    fun list(): List<Map<String, Any?>> {
        val jobs = engine.list().filter { j ->
            // A finished file someone deleted in the Files app.
            j.private || j.status != "done" || j.uri?.let { storedInfo(Uri.parse(it)) } != null
        }
        val all = entries()
        val kept = ArrayList<JSONObject>()
        val out = ArrayList<Map<String, Any?>>()
        for (e in all) {
            val info = if (e.has("dm")) managedInfo(e.getLong("dm")) else storedInfo(Uri.parse(e.getString("uri")))
            if (info == null) continue
            kept.add(e)
            out.add(
                mapOf(
                    "key" to e.getString("key"),
                    "name" to e.getString("name"),
                    "mime" to e.optString("mime"),
                    "time" to e.getLong("time"),
                    "private" to false,
                ) + info,
            )
        }
        if (kept.size != all.size) store(kept)
        return (jobs.map { it.toMap() } + out.reversed()).sortedByDescending { (it["time"] as? Long) ?: 0L }
    }

    private fun managedInfo(id: Long): Map<String, Any?>? {
        val dm = manager ?: return null
        dm.query(DownloadManager.Query().setFilterById(id))?.use { c ->
            if (!c.moveToFirst()) return null
            val status = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_SUCCESSFUL -> "done"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                else -> "running"
            }
            return mapOf(
                "status" to status,
                "bytes" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "total" to c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)),
            )
        }
        return null
    }

    private fun storedInfo(uri: Uri): Map<String, Any?>? = try {
        context.contentResolver.query(uri, arrayOf(MediaStore.Downloads.SIZE), null, null, null)?.use { c ->
            if (!c.moveToFirst()) {
                null
            } else {
                val size = c.getLong(0)
                mapOf("status" to "done", "bytes" to size, "total" to size)
            }
        }
    } catch (e: Exception) {
        null
    }

    private fun find(key: String): JSONObject? = entries().firstOrNull { it.optString("key") == key }

    /**
     * What another app may be handed for [key]: a finished download's
     * Downloads entry, or for a private one a plain copy in the app's cache
     * (deleted with the private session) shared through [PrivateFiles].
     * Null when it isn't one of the engine's downloads.
     */
    private fun engineTarget(key: String): Pair<JSONObject, List<Uri>>? {
        val job = engine.job(key) ?: return null
        val info = JSONObject().put("name", job.name).put("mime", job.mime)
        if (job.status != "done") return info to emptyList()
        if (job.private) {
            val copy = engine.privateCopy(key) ?: return info to emptyList()
            val uri = try {
                FileProvider.getUriForFile(context, PrivateFiles.authority(context), copy)
            } catch (e: Exception) {
                null
            }
            return info to listOfNotNull(uri)
        }
        return info to listOfNotNull(job.uri?.let(Uri::parse))
    }

    /**
     * The links another app may be handed for this file, best first.
     *
     * A web download's own link from the download manager
     * (content://downloads/all_downloads/..) can't be passed on: Android
     * refuses with a SecurityException, so opening and sharing did nothing.
     * The file's MediaStore entry (which ZT Browser owns) can be, so that
     * goes first; the download manager's link stays as a last try.
     */
    private fun urisOf(e: JSONObject): List<Uri> {
        if (!e.has("dm")) return listOfNotNull(e.optString("uri").takeIf { it.isNotEmpty() }?.let(Uri::parse))
        val id = e.getLong("dm")
        val dm = manager ?: return emptyList()
        val out = ArrayList<Uri>()
        var fileName: String? = null
        try {
            dm.query(DownloadManager.Query().setFilterById(id))?.use { c ->
                if (c.moveToFirst()) {
                    val media = c.getColumnIndex("mediaprovider_uri")
                    if (media >= 0) c.getString(media)?.takeIf { it.isNotEmpty() }?.let { out.add(Uri.parse(it)) }
                    val local = c.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
                    if (local >= 0) fileName = c.getString(local)?.let { Uri.parse(it).lastPathSegment }
                }
            }
        } catch (ex: Exception) {
            // Fall through to the lookups below.
        }
        // The download manager may have renamed the file ("report-1.pdf").
        mediaStoreUri(fileName ?: e.optString("name"))?.let { if (it !in out) out.add(it) }
        try {
            dm.getUriForDownloadedFile(id)?.let { if (it !in out) out.add(it) }
        } catch (ex: Exception) {
            // Not finished, or removed.
        }
        return out
    }

    /** This app's own file of that name in Downloads, if MediaStore has it. */
    private fun mediaStoreUri(name: String): Uri? {
        if (name.isEmpty()) return null
        return try {
            context.contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(BaseColumns._ID),
                "${MediaStore.Downloads.DISPLAY_NAME} = ?",
                arrayOf(name),
                "${MediaStore.Downloads.DATE_ADDED} DESC",
            )?.use { c ->
                if (c.moveToFirst()) ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, c.getLong(0)) else null
            }
        } catch (ex: Exception) {
            null
        }
    }

    /** A type other apps can match: the saved one, or one from the file. */
    private fun typeOf(e: JSONObject, uri: Uri): String {
        val resolved = try { context.contentResolver.getType(uri) } catch (ex: Exception) { null }
        return pickMime(e.optString("mime"), resolved, e.optString("name"))
    }

    /**
     * Opens the file in an app that can show it: "opened", "noApp" (nothing
     * on this phone opens that kind of file), "missing" (the file is gone)
     * or "failed".
     */
    fun open(key: String): String {
        val target = engineTarget(key)
        val e = target?.first ?: find(key) ?: return "missing"
        val uris = target?.second ?: urisOf(e)
        if (uris.isEmpty()) return "missing"
        var noApp = false
        for (uri in uris) {
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, typeOf(e, uri))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.clipData = ClipData.newRawUri(e.optString("name"), uri)
            try {
                context.startActivity(intent)
                return "opened"
            } catch (ex: ActivityNotFoundException) {
                noApp = true
            } catch (ex: Exception) {
                // SecurityException: this link can't be passed on; try the next.
            }
        }
        return if (noApp) "noApp" else "failed"
    }

    /** The share sheet for the file: "opened", "missing" or "failed". */
    fun share(key: String): String {
        val target = engineTarget(key)
        val e = target?.first ?: find(key) ?: return "missing"
        val uris = target?.second ?: urisOf(e)
        if (uris.isEmpty()) return "missing"
        for (uri in uris) {
            val send = Intent(Intent.ACTION_SEND)
                .setType(typeOf(e, uri))
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            send.clipData = ClipData.newRawUri(e.optString("name"), uri)
            try {
                context.startActivity(
                    Intent.createChooser(send, null)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
                )
                return "opened"
            } catch (ex: Exception) {
                // Try the next link.
            }
        }
        return "failed"
    }

    /** The phone's own Downloads folder, for files no app here opens. */
    fun showFolder(): Boolean {
        val intents = listOf(
            Intent(DownloadManager.ACTION_VIEW_DOWNLOADS),
            Intent(Intent.ACTION_VIEW).setDataAndType(
                Uri.parse("content://com.android.externalstorage.documents/root/primary"),
                "vnd.android.document/root",
            ),
        )
        for (i in intents) {
            try {
                context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (ex: Exception) {
                // Try the next.
            }
        }
        return false
    }

    /** Deletes the file from the phone, or cancels a running download. */
    @Synchronized
    fun delete(key: String) {
        if (engine.job(key) != null) {
            engine.delete(key)
            return
        }
        val all = entries()
        val e = all.firstOrNull { it.optString("key") == key } ?: return
        try {
            if (e.has("dm")) manager?.remove(e.getLong("dm"))
            else context.contentResolver.delete(Uri.parse(e.getString("uri")), null, null)
        } catch (ex: Exception) {
            // Already gone.
        }
        store(all.filter { it.optString("key") != key })
    }

    companion object {
        /** Types sites send when they don't say what the file is. */
        private val VAGUE = setOf(
            "", "*/*", "application/octet-stream", "binary/octet-stream",
            "application/force-download", "application/download", "application/x-download",
            "application/unknown", "application/binary",
        )

        /**
         * The most specific of the type the site sent, the type Android has
         * for the file, and the type its extension means. Viewers match on
         * type, so "application/octet-stream" for a PDF finds no app.
         */
        fun pickMime(saved: String?, resolved: String?, name: String): String {
            fun specific(t: String?) = t?.trim()?.lowercase()?.substringBefore(';')?.trim()?.takeIf { it !in VAGUE }
            specific(saved)?.let { return it }
            specific(resolved)?.let { return it }
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext.isNotEmpty()) {
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.let { return it }
            }
            return "*/*"
        }

        /** The bytes of a `data:` URL, base64 or percent-encoded. */
        fun decodeDataUrl(url: String): ByteArray? {
            if (!url.startsWith("data:")) return null
            val comma = url.indexOf(',')
            if (comma < 0) return null
            val meta = url.substring(5, comma)
            val payload = url.substring(comma + 1)
            return if (meta.split(';').any { it.equals("base64", ignoreCase = true) }) {
                Base64.decode(payload, Base64.DEFAULT)
            } else {
                percentDecode(payload)
            }
        }

        /** %XX escapes straight to bytes, so binary content survives. */
        fun percentDecode(s: String): ByteArray {
            val out = java.io.ByteArrayOutputStream(s.length)
            var i = 0
            while (i < s.length) {
                val c = s[i]
                if (c == '%' && i + 2 < s.length) {
                    val hi = Character.digit(s[i + 1], 16)
                    val lo = Character.digit(s[i + 2], 16)
                    if (hi >= 0 && lo >= 0) {
                        out.write(hi * 16 + lo)
                        i += 3
                        continue
                    }
                }
                if (c.code < 0x80) {
                    out.write(c.code)
                } else {
                    out.write(c.toString().toByteArray(Charsets.UTF_8))
                }
                i++
            }
            return out.toByteArray()
        }

        /** Adds the usual extension for [mime] when [name] has none. */
        fun withExtension(name: String, mime: String?): String {
            if (name.contains('.') && !name.endsWith(".bin")) return name
            val ext = mime?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) } ?: return name
            return name.removeSuffix(".bin") + "." + ext
        }
    }
}
