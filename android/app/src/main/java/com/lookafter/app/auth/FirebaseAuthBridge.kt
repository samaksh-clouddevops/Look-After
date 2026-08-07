package com.lookafter.app.auth

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Optional Firebase Auth bridge via reflection.
 * Works when `com.google.firebase:firebase-auth` is on the classpath
 * and `google-services.json` is present; otherwise all methods no-op/fail softly.
 */
object FirebaseAuthBridge {

    private const val TAG = "FirebaseAuth"

    fun isAvailable(): Boolean =
        runCatching { Class.forName("com.google.firebase.auth.FirebaseAuth") }.isSuccess

    fun currentUserId(): String? = runCatching {
        val auth = authInstance() ?: return null
        val user = auth.javaClass.getMethod("getCurrentUser").invoke(auth) ?: return null
        user.javaClass.getMethod("getUid").invoke(user) as? String
    }.getOrNull()

    fun currentDisplayName(): String? = runCatching {
        val auth = authInstance() ?: return null
        val user = auth.javaClass.getMethod("getCurrentUser").invoke(auth) ?: return null
        (user.javaClass.getMethod("getDisplayName").invoke(user) as? String)
            ?: (user.javaClass.getMethod("getEmail").invoke(user) as? String)
    }.getOrNull()

    fun currentEmail(): String? = runCatching {
        val auth = authInstance() ?: return null
        val user = auth.javaClass.getMethod("getCurrentUser").invoke(auth) ?: return null
        user.javaClass.getMethod("getEmail").invoke(user) as? String
    }.getOrNull()

    suspend fun signInAnonymously(): Result<AuthUser> = withContext(Dispatchers.IO) {
        runCatching {
            val auth = authInstance() ?: error("Firebase Auth unavailable")
            val task = auth.javaClass.getMethod("signInAnonymously").invoke(auth)
            awaitTask(task)
            val uid = currentUserId() ?: error("No uid after anonymous sign-in")
            AuthUser(
                id = uid,
                displayName = currentDisplayName() ?: "You",
                email = currentEmail().orEmpty(),
                isAnonymous = true,
            )
        }.onFailure { Log.w(TAG, "Anonymous sign-in failed: ${it.message}") }
    }

    suspend fun signInWithEmail(email: String, password: String): Result<AuthUser> =
        withContext(Dispatchers.IO) {
            runCatching {
                val auth = authInstance() ?: error("Firebase Auth unavailable")
                val task = auth.javaClass
                    .getMethod("signInWithEmailAndPassword", String::class.java, String::class.java)
                    .invoke(auth, email.trim(), password)
                awaitTask(task)
                val uid = currentUserId() ?: error("No uid after email sign-in")
                AuthUser(
                    id = uid,
                    displayName = currentDisplayName() ?: email.substringBefore("@"),
                    email = currentEmail() ?: email.trim(),
                    isAnonymous = false,
                )
            }.onFailure { Log.w(TAG, "Email sign-in failed: ${it.message}") }
        }

    fun signOut() {
        runCatching {
            val auth = authInstance() ?: return
            auth.javaClass.getMethod("signOut").invoke(auth)
        }.onFailure { Log.w(TAG, "Sign-out failed: ${it.message}") }
    }

    private fun authInstance(): Any? = runCatching {
        val clazz = Class.forName("com.google.firebase.auth.FirebaseAuth")
        clazz.getMethod("getInstance").invoke(null)
    }.getOrNull()

    private fun awaitTask(task: Any?) {
        if (task == null) return
        val tasksClazz = Class.forName("com.google.android.gms.tasks.Tasks")
        tasksClazz.getMethod("await", Class.forName("com.google.android.gms.tasks.Task"))
            .invoke(null, task)
    }
}
