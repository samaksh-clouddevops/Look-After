package com.lookafter.app.adhd

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin

/**
 * Soft procedural "body double" ambient tone during focus sessions.
 * Generated sine PCM (no asset files) — low volume brownish pad.
 * Safe no-op if audio focus / decoding fails.
 */
class BodyDoubleAmbientAudio(context: Context) {

    private val appContext = context.applicationContext
    private var soundPool: SoundPool? = null
    private var soundId: Int = 0
    private var streamId: Int = 0
    private var playing: Boolean = false

    val isPlaying: Boolean get() = playing

    fun start(emergency: Boolean = false) {
        if (playing) return
        runCatching {
            ensurePool()
            if (soundId == 0) {
                soundId = loadGeneratedTone(emergency)
            }
            if (soundId == 0) return
            val volume = if (emergency) 0.18f else 0.12f
            streamId = soundPool?.play(soundId, volume, volume, 1, -1, 1f) ?: 0
            playing = streamId != 0
            Log.d(TAG, "Ambient started emergency=$emergency")
        }.onFailure {
            Log.w(TAG, "Ambient start failed", it)
            playing = false
        }
    }

    fun stop() {
        if (!playing) return
        runCatching {
            if (streamId != 0) soundPool?.stop(streamId)
        }
        streamId = 0
        playing = false
        Log.d(TAG, "Ambient stopped")
    }

    fun release() {
        stop()
        runCatching { soundPool?.release() }
        soundPool = null
        soundId = 0
    }

    private fun ensurePool() {
        if (soundPool != null) return
        soundPool = SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
    }

    /**
     * Build a short looping soft pad as a temp WAV and load into SoundPool.
     * Prefer AssetFileDescriptor path via cache file.
     */
    private fun loadGeneratedTone(emergency: Boolean): Int {
        val pool = soundPool ?: return 0
        val sampleRate = 22050
        val seconds = 2.0
        val n = (sampleRate * seconds).toInt()
        val freq = if (emergency) 174.0 else 136.1 // Solfeggio-ish calm roots
        val pcm = ShortArray(n)
        for (i in 0 until n) {
            val t = i.toDouble() / sampleRate
            // Soft envelope at ends for loop smoothness
            val env = (sin(Math.PI * i / n)).coerceIn(0.0, 1.0)
            val sample = (
                0.55 * sin(2 * Math.PI * freq * t) +
                    0.25 * sin(2 * Math.PI * (freq * 1.5) * t) +
                    0.12 * sin(2 * Math.PI * (freq * 2.0) * t)
                ) * env
            // mild soft-clip
            val clipped = sample.coerceIn(-1.0, 1.0)
            pcm[i] = (clipped * Short.MAX_VALUE * 0.35).toInt().toShort()
        }
        val wav = writeWav(pcm, sampleRate)
        val file = appContext.cacheDir.resolve(if (emergency) "bd_emerg.wav" else "bd_calm.wav")
        file.writeBytes(wav)
        return pool.load(file.absolutePath, 1)
    }

    private fun writeWav(pcm: ShortArray, sampleRate: Int): ByteArray {
        val dataSize = pcm.size * 2
        val out = ByteArray(44 + dataSize)
        fun wStr(o: Int, s: String) {
            s.toByteArray(Charsets.US_ASCII).copyInto(out, o)
        }
        fun w32(o: Int, v: Int) {
            out[o] = (v and 0xff).toByte()
            out[o + 1] = (v shr 8 and 0xff).toByte()
            out[o + 2] = (v shr 16 and 0xff).toByte()
            out[o + 3] = (v shr 24 and 0xff).toByte()
        }
        fun w16(o: Int, v: Int) {
            out[o] = (v and 0xff).toByte()
            out[o + 1] = (v shr 8 and 0xff).toByte()
        }
        wStr(0, "RIFF"); w32(4, 36 + dataSize); wStr(8, "WAVE")
        wStr(12, "fmt "); w32(16, 16); w16(20, 1); w16(22, 1)
        w32(24, sampleRate); w32(28, sampleRate * 2); w16(32, 2); w16(34, 16)
        wStr(36, "data"); w32(40, dataSize)
        var o = 44
        for (s in pcm) {
            w16(o, s.toInt()); o += 2
        }
        return out
    }

    companion object {
        private const val TAG = "BodyDoubleAudio"
    }
}
