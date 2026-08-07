package com.lookafter.core.planning

import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant

/**
 * Encode/decode [PlanProposal] for LLM round-trips.
 * Tolerates fenced markdown ```json blocks from chat models.
 */
object PlanProposalJson {

    private val json = LookAfterJson.codec

    fun encode(proposal: PlanProposal): String =
        json.encodeToString(PlanProposal.serializer(), proposal)

    fun decode(raw: String): PlanProposal? {
        val cleaned = stripFences(raw).trim()
        if (cleaned.isEmpty()) return null
        // Prefer object spanning first { ... last }
        val start = cleaned.indexOf('{')
        val end = cleaned.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        val slice = cleaned.substring(start, end + 1)
        return runCatching {
            json.decodeFromString(PlanProposal.serializer(), slice)
        }.getOrNull()?.let { decoded ->
            if (decoded.generatedAt == Instant.EPOCH) {
                decoded.copy(generatedAt = Instant.now())
            } else {
                decoded
            }
        }
    }

    fun stripFences(raw: String): String {
        var s = raw.trim()
        if (s.startsWith("```")) {
            s = s.removePrefix("```json").removePrefix("```JSON").removePrefix("```")
            val fence = s.lastIndexOf("```")
            if (fence >= 0) s = s.substring(0, fence)
        }
        return s.trim()
    }

    /** Schema reminder embedded in LLM system prompts. */
    const val SCHEMA_HINT: String = """
Return ONLY JSON matching:
{
  "summary": "string",
  "dayHorizon": 1-7,
  "mutations": [
    {"type":"createTask","title":"...","durationMinutes":30,"constraint":"FLEXIBLE|ANCHORED|FLUID","priority":"HIGH|MEDIUM|LOW","day":"yyyy-MM-dd","hour":9,"minute":0,"notes":"","tags":[]},
    {"type":"completeTask","taskId":"..."},
    {"type":"parkTask","taskId":"...","reason":"plan"},
    {"type":"moveToSomeday","taskId":"..."},
    {"type":"rescheduleTask","taskId":"...","day":"yyyy-MM-dd","hour":10,"minute":0,"durationMinutes":30},
    {"type":"updateTitle","taskId":"...","title":"..."},
    {"type":"deleteTask","taskId":"..."}
  ]
}
Use existing taskIds when mutating. Never invent medication times.
"""
}
