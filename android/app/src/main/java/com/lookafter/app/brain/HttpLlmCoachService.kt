package com.lookafter.app.brain

import android.util.Log
import com.lookafter.core.brain.CoachService
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.TaskStatus
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * OpenAI-compatible Chat Completions coach (HTTPS).
 * Returns empty string on missing key / HTTP error so [com.lookafter.core.brain.FallbackCoachService]
 * can fall back to the offline engine.
 */
class HttpLlmCoachService(
    private val apiKey: String,
    private val baseUrl: String = "https://api.openai.com/v1",
    private val model: String = "gpt-4o-mini",
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    },
    private val connectTimeoutMs: Int = 12_000,
    private val readTimeoutMs: Int = 45_000,
) : CoachService {

    val isConfigured: Boolean
        get() = apiKey.isNotBlank()

    override suspend fun reply(
        userMessage: String,
        life: LifeState,
        health: HealthSummary,
        now: Instant,
    ): String = withContext(Dispatchers.IO) {
        if (!isConfigured) return@withContext ""
        val tick = ExecutiveBrainEngine.tick(life, health, now)
        val system = buildSystemPrompt(life, health, tick.decision.heroTitle, tick.decision.reason)
        runCatching { postChat(system, userMessage.trim()) }
            .onFailure { Log.w(TAG, "LLM coach failed: ${it.message}") }
            .getOrNull()
            .orEmpty()
            .trim()
    }

    private fun buildSystemPrompt(
        life: LifeState,
        health: HealthSummary,
        hero: String,
        reason: String,
    ): String {
        val open = life.activeTasks.filter { it.status.isActive }.take(8)
        val openLines = if (open.isEmpty()) {
            "- none"
        } else {
            open.joinToString("\n") {
                "- ${it.title} (${it.constraintType.name.lowercase()}, ${it.durationMinutes}m)"
            }
        }
        val meds = life.medications.take(6).joinToString(", ") {
            "${it.name}${if (it.isTaken) "✓" else ""}"
        }.ifBlank { "none" }
        val readiness = health.readinessScore?.let { "%.0f%%".format(it * 100) } ?: "unknown"
        return """
            You are Look After, a calm executive coach for ADHD-aware life execution.
            Be brief (2-4 sentences). Never invent medication times. Prefer one next action.
            Hero task: $hero — $reason
            Open tasks:
            $openLines
            Medications: $meds
            Health readiness: $readiness
            Sleep hours: ${health.sleepHours ?: "unknown"}
        """.trimIndent()
    }

    private fun postChat(system: String, user: String): String {
        val endpoint = baseUrl.trimEnd('/') + "/chat/completions"
        val body = ChatRequest(
            model = model,
            messages = listOf(
                ChatMessage(role = "system", content = system),
                ChatMessage(role = "user", content = user),
            ),
            temperature = 0.4,
            maxTokens = 220,
        )
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $apiKey")
        }
        try {
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { w ->
                w.write(json.encodeToString(body))
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.use { BufferedReader(InputStreamReader(it, Charsets.UTF_8)).readText() }
                .orEmpty()
            if (code !in 200..299) {
                Log.w(TAG, "LLM HTTP $code: ${text.take(240)}")
                return ""
            }
            val parsed = json.decodeFromString(ChatResponse.serializer(), text)
            return parsed.choices.firstOrNull()?.message?.content.orEmpty()
        } finally {
            conn.disconnect()
        }
    }

    @Serializable
    private data class ChatRequest(
        val model: String,
        val messages: List<ChatMessage>,
        val temperature: Double = 0.4,
        @SerialName("max_tokens") val maxTokens: Int = 220,
    )

    @Serializable
    private data class ChatMessage(
        val role: String,
        val content: String,
    )

    @Serializable
    private data class ChatResponse(
        val choices: List<Choice> = emptyList(),
    ) {
        @Serializable
        data class Choice(val message: ChatMessage? = null)
    }

    companion object {
        private const val TAG = "HttpLlmCoach"
    }
}
