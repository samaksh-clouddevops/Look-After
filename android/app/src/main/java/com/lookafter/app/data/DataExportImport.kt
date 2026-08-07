package com.lookafter.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.lookafter.core.engine.LifeState
import com.lookafter.core.serialization.LookAfterJson
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Export / import LifeState JSON for backup & support.
 * Share via system sheet; SAF open/create document; parse from string.
 */
object DataExportImport {

    const val MIME_JSON = "application/json"
    const val DEFAULT_EXPORT_NAME = "lookafter-life-backup.json"

    fun encode(state: LifeState): String =
        LookAfterJson.codec.encodeToString(LifeState.serializer(), state)

    fun exportToCache(context: Context, state: LifeState): File {
        val dir = File(context.cacheDir, "exports").also { it.mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "lookafter-life-$stamp.json")
        file.writeText(encode(state))
        return file
    }

    fun shareIntent(context: Context, file: File): Intent {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            context.packageName + ".fileprovider",
            file,
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = MIME_JSON
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "Look After backup")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    fun parseImport(json: String): Result<LifeState> = runCatching {
        LookAfterJson.codec.decodeFromString(LifeState.serializer(), json.trim())
    }

    /** Read backup JSON from a SAF content [Uri]. */
    fun readUri(context: Context, uri: Uri): Result<String> = runCatching {
        context.contentResolver.openInputStream(uri).use { stream ->
            requireNotNull(stream) { "Unable to open $uri" }
            BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).readText()
        }
    }

    /** Write LifeState JSON to a SAF create-document [Uri]. */
    fun writeUri(context: Context, uri: Uri, state: LifeState): Result<Unit> = runCatching {
        context.contentResolver.openOutputStream(uri).use { stream ->
            requireNotNull(stream) { "Unable to write $uri" }
            stream.write(encode(state).toByteArray(Charsets.UTF_8))
            stream.flush()
        }
    }

    fun importUri(context: Context, uri: Uri): Result<LifeState> =
        readUri(context, uri).mapCatching { parseImport(it).getOrThrow() }

    fun prettySummary(state: LifeState): String =
        buildString {
            appendLine("active=${state.activeTasks.size}")
            appendLine("parked=${state.parkedQueue.size}")
            appendLine("someday=${state.somedayVault.size}")
            appendLine("meds=${state.medications.size}")
            appendLine("day=${state.currentDay}")
        }
}
