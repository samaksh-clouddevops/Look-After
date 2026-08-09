package com.lookafter.app.brain

import android.util.Log
import com.lookafter.core.brain.BrainContextPack
import com.lookafter.core.brain.ExecutiveBrainEngine
import com.lookafter.core.engine.LifeState
import com.lookafter.core.health.HealthSummary
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
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Multi-day LLM planner — requests JSON [PlanProposal] from an OpenAI-compatible API.
 * Supports SSE streaming via [streamPlan]; falls back to [MultiDayPlanEngine] on failure.
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
    private val streamingClient: StreamingLlmClient = StreamingLlmClient(apiKey, baseUrl, model),
) {
    val isConfigured: Boolean get() = apiKey.isNotBlank()

    data class PlanResult(
        val proposal: PlanProposal,
        val source: Source,
        val conversationalReply: String,
    ) {
        enum class Source { LLM, OFFLINE, LLM_STREAM }
    }

    /** Progressive UI events while a plan is streaming. */
    sealed class PlanStreamEvent {
        data class Draft(val chars: Int, val preview: String) : PlanStreamEvent()
        data class Complete(val result: PlanResult) : PlanStreamEvent()
    }

    suspend fun plan(
        message: String,
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        today: LocalDate = state.currentDay ?: LocalDate.now(),
        horizonDays: Int = 3,
    ): PlanResult = withContext(Dispatchers.IO) {
        val offline = MultiDayPlanEngine.interpret(message, state, today, horizonDays)
        if (!isConfigured) {
            return@withContext PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
        }
        val llmProposal = runCatching {
            val raw = postChat(buildSystem(state, health, today, horizonDays), message.trim())
            PlanProposalJson.decode(raw)
        }.onFailure {
            Log.w(TAG, "LLM plan failed: ${it.message}")
        }.getOrNull()

        if (llmProposal != null && llmProposal.mutations.isNotEmpty()) {
            PlanResult(
                proposal = llmProposal.copy(
                    dayHorizon = llmProposal.dayHorizon.coerceAtLeast(horizonDays),
                ),
                source = PlanResult.Source.LLM,
                conversationalReply = llmProposal.summary.ifBlank {
                    "Proposed ${llmProposal.mutations.size} change(s) over ${llmProposal.dayHorizon} day(s)."
                },
            )
        } else {
            PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
        }
    }

    /**
     * Stream plan JSON tokens. Emits [PlanStreamEvent.Draft] as the buffer grows,
     * then a single [PlanStreamEvent.Complete] (LLM stream, non-stream LLM, or offline).
     */
    fun streamPlan(
        message: String,
        state: LifeState,
        health: HealthSummary = HealthSummary.EMPTY,
        today: LocalDate = state.currentDay ?: LocalDate.now(),
        horizonDays: Int = 3,
    ): kotlinx.coroutines.flow.Flow<PlanStreamEvent> = kotlinx.coroutines.flow.flow {
        val offline = MultiDayPlanEngine.interpret(message, state, today, horizonDays)
        if (!isConfigured || !streamingClient.isConfigured) {
            emit(
                PlanStreamEvent.Complete(
                    PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply),
                ),
            )
            return@flow
        }
        val system = buildSystem(state, health, today, horizonDays)
        val assembler = com.lookafter.core.planning.StreamingPlanAssembler()
        var emittedDraft = false
        runCatching {
            streamingClient.streamChat(
                messages = listOf(
                    StreamingLlmClient.ChatMessage("system", system),
                    StreamingLlmClient.ChatMessage("user", message.trim()),
                ),
                temperature = 0.2,
                maxTokens = 900,
            ).collect { delta ->
                assembler.append(delta)
                emittedDraft = true
                val preview = assembler.raw.trim().takeLast(160)
                emit(PlanStreamEvent.Draft(chars = assembler.length, preview = preview))
            }
        }.onFailure {
            Log.w(TAG, "stream plan failed: ${it.message}")
        }

        val finished = assembler.tryParse(streamFinished = true)
        val result = when (finished) {
            is com.lookafter.core.planning.StreamingPlanAssembler.ParseAttempt.Success -> {
                val p = finished.proposal
                if (p.mutations.isNotEmpty()) {
                    PlanResult(
                        proposal = p.copy(dayHorizon = p.dayHorizon.coerceAtLeast(horizonDays)),
                        source = PlanResult.Source.LLM_STREAM,
                        conversationalReply = p.summary.ifBlank {
                            "Proposed ${p.mutations.size} change(s) over ${p.dayHorizon} day(s)."
                        },
                    )
                } else {
                    PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
                }
            }
            else -> {
                // Fall back to non-stream HTTP once if stream yielded nothing useful.
                if (!emittedDraft) {
                    plan(message, state, health, today, horizonDays)
                } else {
                    Log.w(TAG, "stream plan parse failed → offline")
                    PlanResult(offline.proposal, PlanResult.Source.OFFLINE, offline.conversationalReply)
                }
            }
        }
        emit(PlanStreamEvent.Complete(result))
    }.flowOn(Dispatchers.IO)

    private fun buildSystem(
        state: LifeState,
        health: HealthSummary,
        today: LocalDate,
        horizonDays: Int = 3,
    ): String {
        val tick = ExecutiveBrainEngine.tick(state, health)
        val brief = BrainContextPack.plannerBrief(state, tick, horizonDays = horizonDays)
        return """
            You are Look After's multi-day executive planner.
            Today is $today. Horizon=${horizonDays}d. Prefer protecting anchored work. Never invent medication schedules.
            Return ONLY JSON matching the schema (no prose outside JSON).
            $brief
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
