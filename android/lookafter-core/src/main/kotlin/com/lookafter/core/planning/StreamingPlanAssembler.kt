package com.lookafter.core.planning

/**
 * Buffers streamed LLM tokens for a JSON [PlanProposal].
 * Tries progressive parse; only treats a decode as "complete enough" when
 * braces balance and mutations are present (or stream finished).
 */
class StreamingPlanAssembler {

    private val buffer = StringBuilder()

    val raw: String get() = buffer.toString()
    val length: Int get() = buffer.length

    fun append(delta: String) {
        if (delta.isNotEmpty()) buffer.append(delta)
    }

    fun clear() {
        buffer.clear()
    }

    /**
     * Best-effort parse of current buffer.
     * @param streamFinished when true, accept empty-mutation proposals with summary.
     */
    fun tryParse(streamFinished: Boolean = false): ParseAttempt {
        val text = buffer.toString()
        if (text.isBlank()) return ParseAttempt.Empty
        val stripped = PlanProposalJson.stripFences(text)
        if (!bracesBalanced(stripped) && !streamFinished) {
            return ParseAttempt.Partial(preview = stripped.takeLast(120))
        }
        val decoded = PlanProposalJson.decode(text)
            ?: return if (streamFinished) {
                ParseAttempt.Failed(raw = text, reason = "unparseable")
            } else {
                ParseAttempt.Partial(preview = stripped.takeLast(120))
            }
        return when {
            decoded.mutations.isNotEmpty() -> ParseAttempt.Success(decoded)
            streamFinished && decoded.summary.isNotBlank() -> ParseAttempt.Success(decoded)
            streamFinished -> ParseAttempt.Failed(raw = text, reason = "no mutations")
            else -> ParseAttempt.Partial(preview = stripped.takeLast(120))
        }
    }

    sealed class ParseAttempt {
        data object Empty : ParseAttempt()
        data class Partial(val preview: String) : ParseAttempt()
        data class Success(val proposal: PlanProposal) : ParseAttempt()
        data class Failed(val raw: String, val reason: String) : ParseAttempt()
    }

    companion object {
        /** Exposed for unit tests without allocating a full assembler. */
        fun bracesBalanced(text: String): Boolean {
            var depth = 0
            var inString = false
            var escape = false
            for (c in text) {
                if (escape) {
                    escape = false
                    continue
                }
                when {
                    c == '\\' && inString -> escape = true
                    c == '"' -> inString = !inString
                    !inString && c == '{' -> depth++
                    !inString && c == '}' -> {
                        depth--
                        if (depth < 0) return false
                    }
                }
            }
            return depth == 0 && text.contains('{')
        }

        fun parseComplete(raw: String): PlanProposal? =
            StreamingPlanAssembler().apply { append(raw) }
                .tryParse(streamFinished = true)
                .let { (it as? ParseAttempt.Success)?.proposal }
    }
}
