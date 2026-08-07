package com.lookafter.app.brain

import android.util.Log
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
import com.lookafter.core.models.TaskStatus
import com.lookafter.core.planning.MultiDayPlanEngine
import com.lookafter.core.planning.PlanProposal
import com.lookafter.core.planning.PlanProposalJson
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Multi-day LLM planner — requests JSON [PlanProposal] from an OpenAI-compatible API.
 * Falls back to [MultiDayPlanEngine] when unconfigured or parse/HTTP fails.
 */
class HttpLlmPlanService(
    private val apiKey: String,
    private val baseUrl: String = "https://api.openai.com/v1",
    private val model: String = "gpt-4o-mini",
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    },
) {
    val isConfigured: Boolean get() = apiKey.isNotBlank()

    data class PlanResult(
        val proposal: PlanProposal,
        val source: Source,
        val conversationalReply: String,
    ) {
        enum class Source { LLM, OFFLINE }
    }

    suspend fun plan(
        message: String,
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        today: LocalDate = state.currentDay ?: LocalDate.now(),
    ): PlanResult = withContext(Dispatchers.IO) {
        val offline = MultiDayPlanEngine.interpret(message, state, today)
        if (!isConfigured) {
            return@withContext PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
        }
        val llmProposal = runCatching {
            val raw = postChat(buildSystem(state, health, today), message.trim())
            PlanProposalJson.decode(raw)
        }.onFailure {
            Log.w(TAG, "LLM plan failed: ${it.message}")
        }.getOrNull()

        if (llmProposal != null && llmProposal.mutations.isNotEmpty()) {
            PlanResult(
                proposal = llmProposal,
                source = PlanResult.Source.LLM,
                conversationalReply = llmProposal.summary.ifBlank {
                    "Proposed ${llmProposal.mutations.size} change(s) over ${llmProposal.dayHorizon} day(s)."
                },
            )
        } else {
            PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
        }
    }

    private fun buildSystem(state: LifeState, health: HealthSummary, today: LocalDate): String {
        val open = state.activeTasks.filter { it.status.isActive }.take(20)
        val lines = open.joinToString("\n") {
            "- id=${it.id} | ${it.title} | ${it.constraintType} | ${it.priority} | day=${it.scheduledDate} | ${it.durationMinutes}m"
        }.ifBlank { "- none" }
        val readiness = health.readinessScore?.let { "%.0f%%".format(it * 100) } ?: "unknown"
        return """
            You are Look After's multi-day executive planner.
            Today is $today. Prefer protecting anchored work. Never invent medication schedules.
            Open tasks:
            $lines
            Readiness: $readiness
            ${PlanProposalJson.SCHEMA_HINT}
        """.trimIndent()
    }

    private fun postChat(system: String, user: String): String {
        val endpoint = baseUrl.trimEnd('/') + "/chat/completions"
        val body = ChatRequest(
            model = model,
            messages = listOf(
                ChatMessage("system", system),
                ChatMessage("user", user),
            ),
            temperature = 0.2,
            maxTokens = 900,
        )
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 60_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $apiKey")
        }
        try {
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use {
                it.write(json.encodeToString(body))
            }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.use { BufferedReader(InputStreamReader(it, Charsets.UTF_8)).readText() }.orEmpty()
            if (code !in 200..299) {
                Log.w(TAG, "plan HTTP $code ${text.take(200)}")
                return ""
            }
            return json.decodeFromString(ChatResponse.serializer(), text)
                .choices.firstOrNull()?.message?.content.orEmpty()
        } finally {
            conn.disconnect()
        }
    }

    @Serializable
    private data class ChatRequest(
        val model: String,
        val messages: List<ChatMessage>,
        val temperature: Double = 0.2,
        @SerialName("max_tokens") val maxTokens: Int = 900,
    )

    @Serializable
    private data class ChatMessage(val role: String, val content: String)

    @Serializable
    private data class ChatResponse(val choices: List<Choice> = emptyList()) {
        @Serializable
        data class Choice(val message: ChatMessage? = null)
    }

    companion object {
        private const val TAG = "HttpLlmPlan"
    }
}
