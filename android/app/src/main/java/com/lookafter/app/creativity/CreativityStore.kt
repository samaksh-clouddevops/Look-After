package com.lookafter.app.creativity

import android.content.Context
import com.lookafter.core.creativity.CreativityState
import com.lookafter.core.serialization.LookAfterJson
import java.time.Instant

/** Persists creativity boards & sparks locally. */
class CreativityStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(): CreativityState {
        val raw = prefs.getString(KEY, null) ?: return seedIfEmpty()
        return runCatching {
            LookAfterJson.codec.decodeFromString(CreativityState.serializer(), raw)
        }.getOrElse { seedIfEmpty() }
    }

    fun save(state: CreativityState) {
        prefs.edit()
            .putString(
                KEY,
                LookAfterJson.codec.encodeToString(CreativityState.serializer(), state),
            )
            .apply()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private fun seedIfEmpty(): CreativityState {
        val boards = com.lookafter.core.creativity.CreativityEngine.defaultBoards(Instant.now())
        return CreativityState(
            boards = boards,
            selectedBoardId = boards.firstOrNull()?.id,
        )
    }

    companion object {
        private const val PREFS = "lookafter_creativity"
        private const val KEY = "state_json"
    }
}
