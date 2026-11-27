package kz.bake.navigator

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

class NavigationVoiceHelper(context: Context) : TextToSpeech.OnInitListener {
    private var engine: TextToSpeech? = TextToSpeech(context.applicationContext, this)
    private var ready = false
    private var language = Locale("ru", "RU")

    override fun onInit(status: Int) {
        ready = status == TextToSpeech.SUCCESS
        if (ready) engine?.language = language
    }

    fun setLanguage(languageCode: String): Boolean {
        val requested = if (languageCode.startsWith("kk", true)) Locale("kk", "KZ") else Locale("ru", "RU")
        val tts = engine ?: return false
        if (!ready || tts.isLanguageAvailable(requested) < TextToSpeech.LANG_AVAILABLE) return false
        language = requested
        return tts.setLanguage(language) >= TextToSpeech.LANG_AVAILABLE
    }

    fun speak(text: String) {
        if (ready && text.isNotBlank()) engine?.speak(text, TextToSpeech.QUEUE_ADD, null, "bake-navigation")
    }

    fun release() {
        engine?.stop()
        engine?.shutdown()
        engine = null
        ready = false
    }
}