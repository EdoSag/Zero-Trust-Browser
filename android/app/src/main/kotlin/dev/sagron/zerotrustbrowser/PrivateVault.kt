package dev.sagron.zerotrustbrowser

import android.content.Context
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Files downloaded in private tabs (B33), encrypted on the phone under a
 * key that only ever lives in memory. When the private session ends (the
 * last private tab closes, the Fire button, the app locks or is closed),
 * the key is dropped and the files deleted, so even a file the phone
 * failed to delete can't be read again.
 *
 * File format: "ZTP1" + an 8-byte random prefix, then 64 KiB chunks, each
 * AES-256-GCM with the nonce prefix + chunk number, and the chunk number
 * and "is last" in the associated data (a cut-off file doesn't decrypt).
 */
object PrivateVault {
    const val CHUNK = 64 * 1024
    private const val TAG = 16
    private const val HEADER = 12
    private val MAGIC = byteArrayOf('Z'.code.toByte(), 'T'.code.toByte(), 'P'.code.toByte(), '1'.code.toByte())
    private val random = SecureRandom()

    @Volatile private var key: SecretKey? = null

    fun dir(context: Context): File = File(context.filesDir, "private-downloads")

    /** Decrypted copies handed to another app to open or share. */
    fun openDir(context: Context): File = File(context.cacheDir, "private-open")

    @Synchronized
    private fun key(): SecretKey = key ?: KeyGenerator.getInstance("AES").run {
        init(256, random)
        generateKey()
    }.also { key = it }

    /** Forgets the key and deletes every private download and copy. */
    @Synchronized
    fun wipe(context: Context) {
        key = null
        dir(context).deleteRecursively()
        openDir(context).deleteRecursively()
    }

    /** Plain bytes already safely written to [file]: whole chunks only. */
    fun committedLength(file: File): Long {
        if (!file.exists() || file.length() < HEADER) return 0
        return (file.length() - HEADER) / (CHUNK + TAG) * CHUNK
    }

    private fun aad(index: Int, last: Boolean): ByteArray =
        ByteBuffer.allocate(5).putInt(index).put(if (last) 1 else 0).array()

    private fun nonce(prefix: ByteArray, index: Int): ByteArray =
        ByteBuffer.allocate(12).put(prefix).putInt(index).array()

    /**
     * Writes plain bytes encrypted to [file], continuing after
     * [committedLength] when [resume] (a partial chunk from before is
     * dropped and downloaded again). [finish] seals the last chunk; [close]
     * without it keeps only whole chunks, ready to resume.
     */
    class Writer(
        private val file: File,
        resume: Boolean,
        /** The private session's key; the download vault (B39) passes its own. */
        private val secret: SecretKey = key(),
    ) : OutputStream() {
        private val prefix = ByteArray(8)
        private val raf: RandomAccessFile
        private val buffer = ByteArray(CHUNK)
        private var filled = 0
        private var index: Int
        private var closed = false

        init {
            file.parentFile?.mkdirs()
            raf = RandomAccessFile(file, "rw")
            if (resume && raf.length() >= HEADER) {
                val head = ByteArray(HEADER)
                raf.seek(0)
                raf.readFully(head)
                if (!head.copyOfRange(0, 4).contentEquals(MAGIC)) throw IOException("not a vault file")
                head.copyInto(prefix, 0, 4, HEADER)
                index = ((raf.length() - HEADER) / (CHUNK + TAG)).toInt()
                raf.setLength(HEADER + index.toLong() * (CHUNK + TAG))
                raf.seek(raf.length())
            } else {
                random.nextBytes(prefix)
                raf.setLength(0)
                raf.write(MAGIC)
                raf.write(prefix)
                index = 0
            }
        }

        override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)

        override fun write(b: ByteArray, off: Int, len: Int) {
            var o = off
            var left = len
            while (left > 0) {
                val n = minOf(left, CHUNK - filled)
                System.arraycopy(b, o, buffer, filled, n)
                filled += n
                o += n
                left -= n
                if (filled == CHUNK) seal(false)
            }
        }

        private fun seal(last: Boolean) {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, secret, GCMParameterSpec(128, nonce(prefix, index)))
            c.updateAAD(aad(index, last))
            raf.write(c.doFinal(buffer, 0, filled))
            index++
            filled = 0
        }

        /** Seals the file: everything written so far is the whole file. */
        fun finish() {
            if (closed) return
            seal(true)
            closed = true
            raf.close()
        }

        override fun close() {
            if (closed) return
            closed = true
            raf.close()
        }
    }

    /** Reads a sealed vault file back as plain bytes. */
    fun reader(file: File, secret: SecretKey = key()): InputStream = Reader(file, secret)

    private class Reader(file: File, private val secret: SecretKey) : FilterInputStream(null) {
        private val raf = RandomAccessFile(file, "r")
        private val prefix = ByteArray(8)
        private val chunks: Int
        private var index = 0
        private var plain = ByteArray(0)
        private var pos = 0

        init {
            val head = ByteArray(HEADER)
            raf.readFully(head)
            if (!head.copyOfRange(0, 4).contentEquals(MAGIC)) throw IOException("not a vault file")
            head.copyInto(prefix, 0, 4, HEADER)
            val body = raf.length() - HEADER
            chunks = ((body + CHUNK + TAG - 1) / (CHUNK + TAG)).toInt()
            if (chunks == 0) throw IOException("not sealed")
        }

        private fun next(): Boolean {
            if (index >= chunks) return false
            val last = index == chunks - 1
            val size = if (last) (raf.length() - HEADER - index.toLong() * (CHUNK + TAG)).toInt() else CHUNK + TAG
            val enc = ByteArray(size)
            raf.readFully(enc)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, nonce(prefix, index)))
            c.updateAAD(aad(index, last))
            plain = c.doFinal(enc)
            pos = 0
            index++
            return true
        }

        override fun read(): Int {
            val one = ByteArray(1)
            return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xff
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            while (pos >= plain.size) {
                if (!next()) return -1
            }
            val n = minOf(len, plain.size - pos)
            System.arraycopy(plain, pos, b, off, n)
            pos += n
            return n
        }

        override fun available(): Int = plain.size - pos

        override fun close() = raf.close()
    }
}
