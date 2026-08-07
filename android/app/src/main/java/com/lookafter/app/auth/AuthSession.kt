package com.lookafter.app.auth

import android.content.Context
import com.lookafter.core.serialization.LookAfterJson
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable

@Serializable
data class AuthUser(
    val id: String,
    val displayName: String,
    val email: String = "",
    val isAnonymous: Boolean = true,
)

@Serializable
data class AuthSessionState(
    val user: AuthUser? = null,
    val syncEnabled: Boolean = false,
    val lastSyncEpochMs: Long = 0L,
) {
    val isSignedIn: Boolean get() = user != null
}

/**
 * Local-first auth/session store.
 * Anonymous device identity by default; ready to swap for Firebase Auth later.
 * Sync flag is persisted but remote transport is not implemented yet.
 */
class AuthSessionStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(load())
    val state: StateFlow<AuthSessionState> = _state.asStateFlow()

    fun ensureAnonymous() {
        if (_state.value.user != null) return
        val user = AuthUser(
            id = "anon-" + UUID.randomUUID(),
            displayName = "You",
            isAnonymous = true,
        )
        persist(_state.value.copy(user = user))
    }

    fun signInLocal(displayName: String, email: String = "") {
        val name = displayName.trim().ifEmpty { "You" }
        val user = AuthUser(
            id = "local-" + UUID.randomUUID(),
            displayName = name,
            email = email.trim(),
            isAnonymous = false,
        )
        persist(_state.value.copy(user = user, syncEnabled = false))
    }

    /** Adopt a Firebase (or other remote) identity after successful remote sign-in. */
    fun applyRemoteUser(user: AuthUser) {
        persist(_state.value.copy(user = user, syncEnabled = _state.value.syncEnabled || !user.isAnonymous))
    }

    fun signOutToAnonymous() {
        val user = AuthUser(
            id = "anon-" + UUID.randomUUID(),
            displayName = "You",
            isAnonymous = true,
        )
        persist(AuthSessionState(user = user, syncEnabled = false))
    }

    fun setSyncEnabled(enabled: Boolean) {
        persist(
            _state.value.copy(
                syncEnabled = enabled,
                lastSyncEpochMs = if (enabled) System.currentTimeMillis() else _state.value.lastSyncEpochMs,
            ),
        )
    }

    fun markSyncedNow() {
        persist(_state.value.copy(lastSyncEpochMs = System.currentTimeMillis()))
    }

    private fun load(): AuthSessionState {
        val raw = prefs.getString(KEY, null) ?: return AuthSessionState()
        return runCatching {
            LookAfterJson.codec.decodeFromString(AuthSessionState.serializer(), raw)
        }.getOrDefault(AuthSessionState())
    }

    private fun persist(next: AuthSessionState) {
        _state.value = next
        prefs.edit()
            .putString(KEY, LookAfterJson.codec.encodeToString(AuthSessionState.serializer(), next))
            .apply()
    }

    companion object {
        private const val PREFS = "lookafter_auth"
        private const val KEY = "session_json"
    }
}
