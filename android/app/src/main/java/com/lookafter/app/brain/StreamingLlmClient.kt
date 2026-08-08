package com.lookafter.app.brain

import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * OpenAI-compatible Chat Completions client with **SSE token streaming**.
 * Emits incremental text deltas; callers assemble the final string.
 */
class StreamingLlmClient(
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

    data class ChatMessage(val role: String, val content: String)

    /** Non-streaming convenience. */
    suspend fun complete(
        system: String,
        user: String,
        temperature: Double = 0.4,
        maxTokens: Int = 400,
    ): String {
        if (!isConfigured) return ""
        val sb = StringBuilder()
        streamChat(
            messages = listOf(ChatMessage("system", system), ChatMessage("user", user)),
            temperature = temperature,
            maxTokens = maxTokens,
        ).collect { sb.append(it) }
        return sb.toString()
    }

    /**
     * Stream assistant tokens as a cold [Flow]. Completes when the SSE stream ends.
     * On HTTP/config failure the flow completes empty (no throw).
     */
    fun streamChat(
        messages: List<ChatMessage>,
        temperature: Double = 0.4,
        maxTokens: Int = 400,
    ): Flow<String> = flow {
        if (!isConfigured) return@flow
        val endpoint = baseUrl.trimEnd('/') + "/chat/completions"
        val body = StreamRequest(
            model = model,
            messages = messages.map { Msg(it.role, it.content) },
            temperature = temperature,
            maxTokens = maxTokens,
            stream = true,
        )
        val conn = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 120_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Authorization", "Bearer $apiKey")
            setRequestProperty("Accept", "text/event-stream")
        }
        try {
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use {
                it.write(json.encodeToString(body))
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                val err = conn.errorStream?.bufferedReader()?.readText().orEmpty()
                Log.w(TAG, "stream HTTP $code ${err.take(200)}")
                return@flow
            }
            BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) continue
                    if (!line.startsWith("data:")) continue
                    val data = line.removePrefix("data:").trim()
                    if (data == "[DONE]") break
                    val delta = parseDelta(data) ?: continue
                    if (delta.isNotEmpty()) emit(delta)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "stream failed: ${t.message}")
        } finally {
            conn.disconnect()
        }
    }.flowOn(Dispatchers.IO)

    private fun parseDelta(data: String): String? = runCatching {
        val root = json.parseToJsonElement(data).jsonObject
        val choices = root["choices"]?.jsonArray ?: return null
        val first = choices.firstOrNull()?.jsonObject ?: return null
        val delta = first["delta"]?.jsonObject ?: return null
        delta["content"]?.jsonPrimitive?.content
    }.getOrNull()

    @Serializable
    private data class StreamRequest(
        val model: String,
        val messages: List<Msg>,
        val temperature: Double = 0.4,
        @SerialName("max_tokens") val maxTokens: Int = 400,
        val stream: Boolean = true,
    )

    @Serializable
    private data class Msg(val role: String, val content: String)

    companion object {
        private const val TAG = "StreamingLlm"
    }
}
