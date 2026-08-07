package com.lookafter.app.diagnostics

import android.content.Context
import android.util.Log
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread

/**
 * Lightweight crash / non-fatal reporting.
 * - Always writes last crash to filesDir/crashes
 * - Optionally forwards to Firebase Crashlytics when on classpath
 */
object CrashReporting {

    private const val TAG = "CrashReporting"
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching { persistCrash(appContext, e) }
            runCatching { recordToCrashlytics(e, fatal = true) }
            previous?.uncaughtException(t, e)
        }
        Log.i(TAG, "Uncaught handler installed")
    }

    fun recordNonFatal(throwable: Throwable, message: String? = null) {
        Log.w(TAG, message ?: throwable.message, throwable)
        recordToCrashlytics(throwable, fatal = false, message = message)
    }

    fun log(message: String) {
        Log.i(TAG, message)
        runCatching {
            val clazz = Class.forName("com.google.firebase.crashlytics.FirebaseCrashlytics")
            val instance = clazz.getMethod("getInstance").invoke(null)
            clazz.getMethod("log", String::class.java).invoke(instance, message)
        }
    }

    private fun persistCrash(context: Context, error: Throwable) {
        val dir = File(context.filesDir, "crashes").also { it.mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "crash-$stamp.txt")
        val sw = StringWriter()
        error.printStackTrace(PrintWriter(sw))
        file.writeText(sw.toString())
        // Keep only last 10
        dir.listFiles()
            ?.sortedByDescending { it.lastModified() }
            ?.drop(10)
            ?.forEach { it.delete() }
        Log.e(TAG, "Crash persisted → ${file.absolutePath}")
    }

    private fun recordToCrashlytics(
        error: Throwable,
        fatal: Boolean,
        message: String? = null,
    ) {
        runCatching {
            val clazz = Class.forName("com.google.firebase.crashlytics.FirebaseCrashlytics")
            val instance = clazz.getMethod("getInstance").invoke(null)
            if (!message.isNullOrBlank()) {
                clazz.getMethod("log", String::class.java).invoke(instance, message)
            }
            if (fatal) {
                // recordException is non-fatal; fatal path already killing process
                clazz.getMethod("recordException", Throwable::class.java)
                    .invoke(instance, error)
            } else {
                clazz.getMethod("recordException", Throwable::class.java)
                    .invoke(instance, error)
            }
        }
    }
}
