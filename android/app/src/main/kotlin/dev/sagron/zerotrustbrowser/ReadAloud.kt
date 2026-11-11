package dev.sagron.zerotrustbrowser

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.util.Locale

/**
 * Read aloud (B27) with Android's own text to speech. Only voices that work
 * without a network connection are used, so the page's text stays on the
 * phone; when the language has no such voice, it says so instead.
 *
 * Text arrives in parts (paragraphs); pausing stops after remembering the
 * part, and resuming starts that part again.
 */
class ReadAloud(context: Context, private val report: (Map<String, Any?>) -> Unit) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ready = false
    private var parts: List<String> = emptyList()
    private var index = 0
    private var rate = 1.0f
    private var language: String? = null
    private var status = "idle"

    /** Called when reading starts or stops, for the media notification. */
    var onActive: ((Boolean, String) -> Unit)? = null
    private var title = ""

    /** Starts reading [newParts] from [from]; false when nothing can read. */
    fun start(newParts: List<String>, newTitle: String, lang: String?, newRate: Double, from: Int) {
        stopSpeaking()
        parts = newParts
        title = newTitle
        index = from.coerceIn(0, maxOf(0, newParts.size - 1))
        rate = newRate.toFloat()
        language = lang
        if (parts.isEmpty()) {
            send("idle")
            return
        }
        val engine = tts
        if (engine != null && ready) {
            if (useVoice(engine)) speakCurrent()
            return
        }
        if (engine == null) {
            tts = TextToSpeech(app) { code ->
                main.post {
                    ready = code == TextToSpeech.SUCCESS
                    val t = tts
                    if (!ready || t == null) {
                        send("idle", error = "failed")
                        return@post
                    }
                    t.setOnUtteranceProgressListener(listener)
                    if (parts.isNotEmpty() && useVoice(t)) speakCurrent()
                }
            }
        }
    }

    fun pause() {
        if (status != "speaking") return
        stopSpeaking()
        send("paused")
    }

    fun resume() {
        if (status != "paused" || parts.isEmpty()) return
        val t = tts ?: return
        if (useVoice(t)) speakCurrent()
    }

    fun skip(by: Int) {
        if (parts.isEmpty()) return
        index = (index + by).coerceIn(0, parts.size - 1)
        val t = tts ?: return
        if (status == "speaking" && useVoice(t)) speakCurrent() else send(status)
    }

    fun setRate(newRate: Double) {
        rate = newRate.toFloat()
        tts?.setSpeechRate(rate)
        // Takes effect from the start of the current part.
        if (status == "speaking") tts?.let { if (useVoice(it)) speakCurrent() }
    }

    fun stop() {
        stopSpeaking()
        parts = emptyList()
        index = 0
        send("idle")
    }

    fun shutdown() {
        stopSpeaking()
        tts?.shutdown()
        tts = null
        ready = false
    }

    val isActive: Boolean get() = status == "speaking" || status == "paused"
    val isSpeaking: Boolean get() = status == "speaking"
    val currentTitle: String get() = title

    private fun stopSpeaking() {
        tts?.stop()
    }

    /**
     * Picks an on-device voice for the page's language. Returns false (and
     * reports `noVoice`) when there is none: never falls back to a voice
     * that sends the text to a server.
     */
    private fun useVoice(t: TextToSpeech): Boolean {
        val wanted = language?.takeIf { it.isNotBlank() }?.let { Locale.forLanguageTag(it) }
            ?: Locale.getDefault()
        val voices: Set<Voice> = try {
            t.voices ?: emptySet()
        } catch (e: Exception) {
            emptySet()
        }
        val offline = voices.filter { !it.isNetworkConnectionRequired && !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
        fun same(a: Locale, b: Locale) = a.language == b.language ||
            // Hebrew is "iw" in older Java and "he" in BCP-47.
            (setOf(a.language, b.language) == setOf("iw", "he"))
        val match = offline.filter { same(it.locale, wanted) }
        val best = match.firstOrNull { it.locale.country == wanted.country && wanted.country.isNotEmpty() }
            ?: match.maxByOrNull { it.quality }
        if (best == null) {
            send("idle", error = "noVoice")
            return false
        }
        t.voice = best
        t.setSpeechRate(rate)
        return true
    }

    private fun speakCurrent() {
        val t = tts ?: return
        if (index >= parts.size) {
            send("done")
            return
        }
        val params = Bundle()
        // Ask the engine for its on-device synthesis.
        params.putString(TextToSpeech.Engine.KEY_FEATURE_EMBEDDED_SYNTHESIS, "true")
        params.putString(TextToSpeech.Engine.KEY_FEATURE_NETWORK_SYNTHESIS, "false")
        t.speak(parts[index], TextToSpeech.QUEUE_FLUSH, params, "part-$index")
        send("speaking")
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {}

        override fun onDone(utteranceId: String?) {
            main.post {
                if (status != "speaking" || utteranceId != "part-$index") return@post
                index++
                if (index >= parts.size) {
                    index = 0
                    parts = emptyList()
                    send("done")
                } else {
                    speakCurrent()
                }
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) {
            main.post { if (utteranceId == "part-$index") send("idle", error = "failed") }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) {}
    }

    private fun send(newStatus: String, error: String? = null) {
        val wasActive = isActive
        status = newStatus
        report(mapOf("status" to newStatus, "part" to index, "parts" to parts.size, "error" to error))
        if (wasActive != isActive) onActive?.invoke(isActive, title)
    }
}
