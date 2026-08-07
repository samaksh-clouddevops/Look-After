package com.lookafter.app.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.lookafter.core.engine.LifeState
import com.lookafter.core.serialization.LookAfterJson
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Export / import LifeState JSON for backup & support.
 * Share via system sheet; import from a string/file body.
 */
object DataExportImport {

    fun exportToCache(context: Context, state: LifeState): File {
        val dir = File(context.cacheDir, "exports").also { it.mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "lookafter-life-$stamp.json")
        file.writeText(LookAfterJson.codec.encodeToString(LifeState.serializer(), state))
        return file
    }

    fun shareIntent(context: Context, file: File): Intent {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            context.packageName + ".fileprovider",
            file,
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "Look After backup")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    fun parseImport(json: String): Result<LifeState> = runCatching {
        LookAfterJson.codec.decodeFromString(LifeState.serializer(), json.trim())
    }

    fun prettySummary(state: LifeState): String =
        buildString {
            appendLine("active=${state.activeTasks.size}")
            appendLine("parked=${state.parkedQueue.size}")
            appendLine("someday=${state.somedayVault.size}")
            appendLine("meds=${state.medications.size}")
            appendLine("day=${state.currentDay}")
        }
}
