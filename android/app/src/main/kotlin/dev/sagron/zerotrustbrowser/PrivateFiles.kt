package dev.sagron.zerotrustbrowser

import android.content.Context
import androidx.core.content.FileProvider

/**
 * Hands another app a plain copy of a private download (B33) to open or
 * share, from the app's cache only (res/xml/private_download_paths.xml).
 * The copies are deleted when the private session ends. Its own class so
 * it never clashes with a plugin's file provider.
 */
class PrivateFiles : FileProvider() {
    companion object {
        fun authority(context: Context) = "${context.packageName}.privatefiles"
    }
}
