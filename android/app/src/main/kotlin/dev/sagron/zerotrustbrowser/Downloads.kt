package dev.sagron.zerotrustbrowser

import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.util.Base64
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * The files ZT Browser downloaded, for the Downloads page: web downloads
 * through the system download manager, and data:/blob: files the page made
 * itself, written to Downloads directly. The list (names, not contents)
 * stays on this phone.
 */
class Downloads(private val context: Context) {
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

    @Synchronized
    fun addManaged(id: Long, name: String, mime: String?) {
        store(entries() + entry(name, mime).put("dm", id))
    }

    /** Writes [bytes] to the phone's Downloads folder. */
    @Synchronized
    fun saveBytes(bytes: ByteArray, name: String, mime: String): Boolean {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: throw IllegalStateException("no stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            return false
        }
        store(entries() + entry(name, mime).put("uri", uri.toString()))
        return true
    }

    private fun entry(name: String, mime: String?) = JSONObject()
        .put("key", UUID.randomUUID().toString())
        .put("name", name)
        .put("mime", mime ?: "application/octet-stream")
        .put("time", System.currentTimeMillis())

    /** Newest first, with progress; files deleted elsewhere drop out. */
    @Synchronized
    fun list(): List<Map<String, Any?>> {
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
                ) + info,
            )
        }
        if (kept.size != all.size) store(kept)
        return out.reversed()
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

    private fun uriOf(e: JSONObject): Uri? =
        if (e.has("dm")) manager?.getUriForDownloadedFile(e.getLong("dm")) else Uri.parse(e.getString("uri"))

    /** Opens the file in an app that can show it; false when none can. */
    fun open(key: String): Boolean {
        val e = find(key) ?: return false
        val uri = uriOf(e) ?: return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, e.optString("mime", "*/*"))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (ex: ActivityNotFoundException) {
            false
        }
    }

    fun share(key: String): Boolean {
        val e = find(key) ?: return false
        val uri = uriOf(e) ?: return false
        val send = Intent(Intent.ACTION_SEND)
            .setType(e.optString("mime", "*/*"))
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            context.startActivity(
                Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (ex: ActivityNotFoundException) {
            false
        }
    }

    /** Deletes the file from the phone, or cancels a running download. */
    @Synchronized
    fun delete(key: String) {
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
                Uri.decode(payload).toByteArray(Charsets.UTF_8)
            }
        }

        /** Adds the usual extension for [mime] when [name] has none. */
        fun withExtension(name: String, mime: String?): String {
            if (name.contains('.') && !name.endsWith(".bin")) return name
            val ext = mime?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) } ?: return name
            return name.removeSuffix(".bin") + "." + ext
        }
    }
}
