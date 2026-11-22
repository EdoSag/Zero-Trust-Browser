package dev.sagron.zerotrustbrowser

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/**
 * B39: the download vault. Files kept encrypted inside the app, on this
 * phone only, never synced or backed up. Other apps and the Files app
 * can't see them; ZT Browser asks for the phone's lock before showing the
 * vault (in Dart).
 *
 * Each file is encrypted with the same chunked AES-256-GCM format as
 * private downloads ([PrivateVault]), under a vault key that is itself
 * stored encrypted by an Android Keystore key ([EncryptedStore]). The list
 * of files (names, sizes) is in an [EncryptedStore] too.
 */
class DownloadVault(context: Context) {
    private val app = context.applicationContext
    private val index = EncryptedStore(app, "vault-index")
    private val keyFile = EncryptedStore(app, "vault-key")
    private val random = SecureRandom()

    init {
        // Plain copies from an earlier visit (the app was closed while open).
        clearOpen()
    }

    private fun dir() = File(app.filesDir, "vault")

    private fun file(id: String) = File(dir(), "$id.ztv")

    /** Plain copies handed to another app to open or share (res/xml paths). */
    private fun openDir() = File(app.cacheDir, "vault-open")

    @Volatile private var key: SecretKey? = null

    @Synchronized
    private fun key(): SecretKey {
        key?.let { return it }
        val stored = keyFile.read()?.let { Base64.decode(it, Base64.NO_WRAP) }
        val bytes = if (stored != null && stored.size == 32) {
            stored
        } else {
            if (dir().list()?.isNotEmpty() == true) {
                // The key is gone (phone restored, Keystore reset): the old
                // files can't be read; never mix them with a new key.
                throw IllegalStateException("vault key missing")
            }
            ByteArray(32).also {
                random.nextBytes(it)
                keyFile.write(Base64.encodeToString(it, Base64.NO_WRAP))
            }
        }
        return SecretKeySpec(bytes, "AES").also { key = it }
    }

    @Synchronized
    private fun entries(): MutableList<JSONObject> {
        val text = index.read() ?: return ArrayList()
        return try {
            val arr = JSONArray(text)
            MutableList(arr.length()) { arr.getJSONObject(it) }
        } catch (e: Exception) {
            ArrayList()
        }
    }

    @Synchronized
    private fun store(list: List<JSONObject>) {
        val arr = JSONArray()
        list.forEach { arr.put(it) }
        index.write(arr.toString())
    }

    private fun find(id: String) = entries().firstOrNull { it.optString("id") == id }

    fun list(): List<Map<String, Any?>> = entries()
        .filter { file(it.optString("id")).isFile }
        .sortedByDescending { it.optLong("time") }
        .map {
            mapOf(
                "id" to it.optString("id"),
                "name" to it.optString("name"),
                "mime" to it.optString("mime"),
                "size" to it.optLong("size"),
                "time" to it.optLong("time"),
            )
        }

    /** Encrypts [input] into the vault as [name]; false when it couldn't. */
    @Synchronized
    fun add(input: InputStream, name: String, mime: String): Boolean {
        val id = UUID.randomUUID().toString()
        val target = file(id)
        var size = 0L
        try {
            input.use { src ->
                val w = PrivateVault.Writer(target, false, key())
                try {
                    val buf = ByteArray(PrivateVault.CHUNK)
                    while (true) {
                        val n = src.read(buf)
                        if (n < 0) break
                        w.write(buf, 0, n)
                        size += n
                    }
                    w.finish()
                } finally {
                    w.close()
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("ZtBrowser", "Not added to the vault", e)
            target.delete()
            return false
        }
        val list = entries()
        list.add(
            JSONObject().put("id", id).put("name", DownloadEngine.cleanName(name).ifEmpty { "file" })
                .put("mime", mime.ifEmpty { "application/octet-stream" })
                .put("size", size).put("time", System.currentTimeMillis()),
        )
        store(list)
        return true
    }

    /** A finished download moved into the vault and off the phone. */
    fun addDownload(engine: DownloadEngine, key: String): Boolean {
        val job = engine.job(key) ?: return false
        val input = engine.openInput(key) ?: return false
        if (!add(input, job.name, job.mime)) return false
        engine.delete(key)
        return true
    }

    /**
     * Files the person picked on the phone. With [move], each original is
     * deleted once it is safely in the vault, where the app holding it
     * allows that. Returns how many were added and how many originals
     * stayed (when moving).
     */
    fun addFromPhone(uris: List<Uri>, move: Boolean): Map<String, Int> {
        var added = 0
        var kept = 0
        val resolver = app.contentResolver
        for (uri in uris) {
            var name = uri.lastPathSegment ?: "file"
            try {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(0)?.takeIf { it.isNotBlank() }?.let { name = it }
                }
            } catch (e: Exception) { }
            val mime = try { resolver.getType(uri) } catch (e: Exception) { null } ?: "application/octet-stream"
            val input = try { resolver.openInputStream(uri) } catch (e: Exception) { null } ?: continue
            if (!add(input, name, mime)) continue
            added++
            if (move) {
                val deleted = try {
                    DocumentsContract.deleteDocument(resolver, uri)
                } catch (e: Exception) {
                    false
                }
                if (!deleted) kept++
            }
        }
        return mapOf("added" to added, "kept" to kept)
    }

    /** A plain copy of [id] for another app, deleted when the vault closes. */
    private fun plainCopy(id: String): Pair<JSONObject, Uri>? {
        val e = find(id) ?: return null
        val src = file(id)
        if (!src.isFile) return null
        val dir = File(openDir(), id).apply { mkdirs() }
        val out = File(dir, e.optString("name").ifEmpty { "file" })
        return try {
            if (!(out.exists() && out.length() == e.optLong("size"))) {
                FileOutputStream(out).use { o -> PrivateVault.reader(src, key()).use { it.copyTo(o, PrivateVault.CHUNK) } }
            }
            e to FileProvider.getUriForFile(app, PrivateFiles.authority(app), out)
        } catch (ex: Exception) {
            out.delete()
            null
        }
    }

    /** "opened", "noApp", "missing" or "failed", like the Downloads page. */
    fun open(id: String): String {
        val (e, uri) = plainCopy(id) ?: return if (find(id) == null) "missing" else "failed"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, Downloads.pickMime(e.optString("mime"), null, e.optString("name")))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.clipData = ClipData.newRawUri(e.optString("name"), uri)
        return try {
            app.startActivity(intent)
            "opened"
        } catch (ex: android.content.ActivityNotFoundException) {
            "noApp"
        } catch (ex: Exception) {
            "failed"
        }
    }

    fun share(id: String): String {
        val (e, uri) = plainCopy(id) ?: return if (find(id) == null) "missing" else "failed"
        val send = Intent(Intent.ACTION_SEND)
            .setType(Downloads.pickMime(e.optString("mime"), null, e.optString("name")))
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(e.optString("name"), uri)
        return try {
            app.startActivity(
                Intent.createChooser(send, null)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            "opened"
        } catch (ex: Exception) {
            "failed"
        }
    }

    /** Takes [id] out of the vault into Downloads (or the picked folder). */
    fun moveToPhone(engine: DownloadEngine, id: String): Boolean {
        val e = find(id) ?: return false
        val src = file(id)
        val ok = engine.saveFromVault(e.optString("name"), e.optString("mime"), e.optLong("size")) { out ->
            PrivateVault.reader(src, key()).use { it.copyTo(out, PrivateVault.CHUNK) }
        }
        if (ok) delete(id)
        return ok
    }

    /** B40: the plain bytes of [id], to send it on. */
    fun reader(id: String): InputStream? = if (file(id).isFile) PrivateVault.reader(file(id), key()) else null

    @Synchronized
    fun rename(id: String, name: String): Boolean {
        val clean = DownloadEngine.cleanName(name)
        if (clean.isEmpty()) return false
        val list = entries()
        val e = list.firstOrNull { it.optString("id") == id } ?: return false
        e.put("name", clean)
        store(list)
        File(openDir(), id).deleteRecursively()
        return true
    }

    @Synchronized
    fun delete(id: String) {
        file(id).delete()
        File(openDir(), id).deleteRecursively()
        store(entries().filter { it.optString("id") != id })
    }

    /** The vault closed (left or locked): plain copies go. */
    fun clearOpen() {
        openDir().deleteRecursively()
    }

    companion object {
        @Volatile private var instance: DownloadVault? = null

        fun get(context: Context): DownloadVault =
            instance ?: synchronized(this) { instance ?: DownloadVault(context).also { instance = it } }
    }
}
