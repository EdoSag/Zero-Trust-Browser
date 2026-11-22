package dev.sagron.zerotrustbrowser

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * B37: a small text file kept encrypted on this phone (AES-256-GCM), with
 * the key in the Android Keystore, where it can't be copied out. Used for
 * the download list, which stays on this phone and is never synced.
 */
class EncryptedStore(context: Context, name: String) {
    private val file = File(File(context.filesDir, "secure"), "$name.bin")

    /** The text, or null when there is none or it can't be read. */
    @Synchronized
    fun read(): String? {
        if (!file.isFile) return null
        return try {
            val data = file.readBytes()
            if (data.size < IV + 16) return null
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, IV))
            String(cipher.doFinal(data, IV, data.size - IV), Charsets.UTF_8)
        } catch (e: Exception) {
            android.util.Log.e("ZtBrowser", "Encrypted store not read", e)
            null
        }
    }

    @Synchronized
    fun write(text: String) {
        try {
            val cipher = Cipher.getInstance(TRANSFORM)
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val iv = cipher.iv
            val sealed = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
            file.parentFile?.mkdirs()
            val tmp = File(file.path + ".tmp")
            tmp.outputStream().use { it.write(iv); it.write(sealed) }
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (e: Exception) {
            android.util.Log.e("ZtBrowser", "Encrypted store not written", e)
        }
    }

    companion object {
        private const val ALIAS = "zt_browser_local_lists"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val IV = 12

        @Synchronized
        private fun key(): SecretKey {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
            val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            gen.init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            return gen.generateKey()
        }
    }
}
