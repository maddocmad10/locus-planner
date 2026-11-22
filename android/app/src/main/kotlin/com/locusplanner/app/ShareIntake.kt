package com.locusplanner.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Durable Android share intake.
 *
 * A share is staged once under an intake UUID. The manifest survives a
 * rotation or process death until Dart commits the task and calls complete()
 * with the same id. Replaying the pending intake must therefore create one
 * task, which Dart guarantees by using the intake id as the task id.
 */
object ShareIntake {
    const val PREFS = "locus_share_intake"
    const val KEY_PENDING = "pending_ids"
    const val MAX_FILES = 20
    const val MAX_FILE_BYTES = 25L * 1024L * 1024L
    const val MAX_PENDING = 20
    private const val MAX_AGE_MS = 24L * 60L * 60L * 1000L

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun handle(
        context: Context,
        intent: Intent?,
        onReady: ((String) -> Unit)? = null,
    ) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND &&
            intent.action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return
        }
        // Copy off the UI thread and count bytes while copying.
        val app = context.applicationContext
        executor.execute {
            val id = UUID.randomUUID().toString()
            val dir = File(app.cacheDir, "share_intake/$id")
            if (!dir.mkdirs()) return@execute
            try {
                val manifest = stage(app, intent, id, dir)
                if (manifest == null || !writeManifestAtomic(dir, manifest)) {
                    dir.deleteRecursively()
                    return@execute
                }
                if (!addPending(app, id)) {
                    dir.deleteRecursively()
                    return@execute
                }
                if (onReady != null) {
                    main.post { onReady(id) }
                }
            } catch (_: Exception) {
                dir.deleteRecursively()
            }
        }
    }

    private fun stage(
        context: Context,
        intent: Intent,
        id: String,
        dir: File,
    ): JSONObject? {
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        val extraText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val clipTexts = mutableListOf<String>()
        val uris = LinkedHashSet<Uri>()

        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                val item = clip.getItemAt(index)
                item.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let {
                    clipTexts.add(it)
                }
                item.uri?.let { uris.add(it) }
            }
        }
        @Suppress("DEPRECATION")
        intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)

        val allText = buildList {
            if (subject.isNotEmpty()) add(subject)
            if (extraText.isNotEmpty()) add(extraText)
            addAll(clipTexts)
        }.joinToString("\n").trim()

        val files = JSONArray()
        val rejected = JSONArray()
        for ((ordinal, uri) in uris.withIndex()) {
            val mime = context.contentResolver.getType(uri)
                ?: intent.type
                ?: "application/octet-stream"
            val name = queryDisplayName(context, uri) ?: "shared-file"
            if (ordinal >= MAX_FILES) {
                rejected.put(
                    JSONObject()
                        .put("name", name)
                        .put("mimeType", mime)
                        .put("ordinal", ordinal)
                        .put("reason", "More than $MAX_FILES files were shared")
                        .put("reasonCode", "too_many_files")
                        .put("retryable", false)
                        .put("status", "rejected"),
                )
                continue
            }
            val safe = name
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
                .take(80)
                .ifBlank { "shared" }
            val target = File(dir, "$ordinal-$safe")
            when (val copy = copyWithLimit(context, uri, target)) {
                is CopyResult.Copied -> {
                    files.put(
                        JSONObject()
                            .put("path", target.absolutePath)
                            .put("name", name)
                            .put("mimeType", mime)
                            .put("bytes", copy.bytes)
                            .put("ordinal", ordinal)
                            // Deterministic per-intake mapping; replaying the
                            // intake reuses the same attachment id.
                            .put("attachmentId", "$id-$ordinal")
                            .put("status", "staged"),
                    )
                }

                is CopyResult.Failed -> {
                    target.delete()
                    rejected.put(
                        JSONObject()
                            .put("name", name)
                            .put("mimeType", mime)
                            .put("ordinal", ordinal)
                            .put("reason", copy.reason)
                            .put("reasonCode", copy.code)
                            .put("retryable", copy.retryable)
                            .put("status", "rejected"),
                    )
                }
            }
        }

        if (allText.isEmpty() && files.length() == 0 && rejected.length() == 0) {
            return null
        }
        val title = when {
            subject.isNotEmpty() -> subject
            allText.isNotEmpty() -> allText.lineSequence()
                .firstOrNull { it.isNotBlank() }
                ?.trim()
                ?: "Shared item"
            files.length() > 0 || rejected.length() > 0 -> "Shared file"
            else -> "Shared item"
        }
        return JSONObject()
            .put("id", id)
            .put("title", title.take(200))
            .put("text", allText)
            .put("files", files)
            .put("rejected", rejected)
            .put("createdAt", System.currentTimeMillis())
    }

    private sealed class CopyResult {
        data class Copied(val bytes: Long) : CopyResult()
        data class Failed(
            val reason: String,
            val code: String,
            val retryable: Boolean,
        ) : CopyResult()
    }

    /// Copies one content URI, distinguishing an unreadable source from a file
    /// over the 25 MB limit and from a full/interrupted destination. The Dart
    /// importer turns the code into a durable retryable or rejected outcome.
    private fun copyWithLimit(
        context: Context,
        uri: Uri,
        target: File,
    ): CopyResult {
        val source = try {
            context.contentResolver.openInputStream(uri)
        } catch (_: Exception) {
            null
        } ?: return CopyResult.Failed(
            "The file could not be read",
            "unreadable",
            retryable = true,
        )
        val sink = try {
            target.outputStream()
        } catch (e: Exception) {
            source.close()
            return CopyResult.Failed(
                storageMessage(e),
                storageCode(e),
                retryable = true,
            )
        }
        sink.use { out ->
            source.use { input ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val read = try {
                        input.read(buffer)
                    } catch (_: Exception) {
                        target.delete()
                        return CopyResult.Failed(
                            "The file could not be read",
                            "unreadable",
                            retryable = true,
                        )
                    }
                    if (read < 0) break
                    total += read
                    if (total > MAX_FILE_BYTES) {
                        target.delete()
                        return CopyResult.Failed(
                            "Files larger than 25 MB are not supported",
                            "too_large",
                            retryable = false,
                        )
                    }
                    try {
                        out.write(buffer, 0, read)
                    } catch (e: Exception) {
                        target.delete()
                        return CopyResult.Failed(
                            storageMessage(e),
                            storageCode(e),
                            retryable = true,
                        )
                    }
                }
                return CopyResult.Copied(total)
            }
        }
    }

    private fun storageCode(error: Exception): String {
        val message = (error.message ?: "").lowercase()
        return if (message.contains("enospc") ||
            message.contains("no space left")
        ) {
            "storage_full"
        } else {
            "storage_error"
        }
    }

    private fun storageMessage(error: Exception): String {
        return if (storageCode(error) == "storage_full") {
            "There is not enough free space to stage the file"
        } else {
            "The file could not be saved to temporary storage"
        }
    }

    fun take(context: Context): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        for (id in pendingIds(context)) {
            val file = File(context.cacheDir, "share_intake/$id/manifest.json")
            if (!file.isFile) continue
            try {
                val json = JSONObject(file.readText())
                // A completed manifest is waiting only for its directory to be
                // removed (crash between the DB commit and this acknowledgement).
                if (json.optBoolean("complete", false)) {
                    removePending(context, id)
                    File(context.cacheDir, "share_intake/$id").deleteRecursively()
                    continue
                }
                result.add(jsonToMap(json))
            } catch (_: Exception) {
                // A damaged manifest is skipped; its directory is swept later.
            }
        }
        return result
    }

    /// Marks the intake complete before removing staged files. A crash after
    /// the task commit but before this call replays safely because Dart reuses
    /// the intake id as the task id and skips an already complete manifest.
    /// Completing an id that is already gone is a no-op.
    fun complete(context: Context, id: String) {
        val dir = File(context.cacheDir, "share_intake/$id")
        try {
            val manifest = File(dir, "manifest.json")
            if (manifest.isFile) {
                val json = JSONObject(manifest.readText()).put("complete", true)
                writeManifestAtomic(dir, json)
            }
        } catch (_: Exception) {
            // The acknowledgement is still idempotent without the marker.
        } finally {
            removePending(context, id)
            dir.deleteRecursively()
        }
    }

    fun sweep(context: Context) {
        val root = File(context.cacheDir, "share_intake")
        if (!root.isDirectory) return
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        // A pending intake may hold retryable staged bytes. Age alone must not
        // delete them; only the importer's complete() call or an explicit user
        // discard may remove the directory.
        val pending = pendingIds(context).toSet()
        root.listFiles()?.forEach { dir ->
            if (!dir.isDirectory) return@forEach
            val manifest = File(dir, "manifest.json")
            if (dir.name in pending) {
                // Keep staged bytes for a retry. A pending id with no manifest
                // is only a crashed acknowledgement; it has nothing to retry.
                if (manifest.isFile) return@forEach
                removePending(context, dir.name)
                dir.deleteRecursively()
                return@forEach
            }
            val keep = manifest.isFile && manifest.lastModified() >= cutoff
            if (!keep) dir.deleteRecursively()
        }
    }

    /// Writes the whole manifest through a synced temporary file, so a crash
    /// while staging never leaves a half-written manifest for Dart to replay.
    private fun writeManifestAtomic(dir: File, manifest: JSONObject): Boolean {
        val target = File(dir, "manifest.json")
        val temp = File(dir, "manifest.json.tmp")
        return try {
            FileOutputStream(temp).use { out ->
                out.write(manifest.toString().toByteArray(Charsets.UTF_8))
                out.flush()
                out.fd.sync()
            }
            if (target.exists() && !target.delete()) return false
            temp.renameTo(target)
        } catch (_: Exception) {
            temp.delete()
            false
        }
    }

    private fun pendingIds(context: Context): List<String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { array.optString(it, "") }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun addPending(context: Context, id: String): Boolean {
        val ids = pendingIds(context).toMutableList()
        if (ids.contains(id)) return true
        ids.add(id)
        while (ids.size > MAX_PENDING) ids.removeAt(0)
        return savePending(context, ids)
    }

    private fun removePending(context: Context, id: String) {
        val ids = pendingIds(context).toMutableList()
        ids.remove(id)
        savePending(context, ids)
    }

    private fun savePending(context: Context, ids: List<String>): Boolean {
        val array = JSONArray()
        ids.forEach(array::put)
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, array.toString())
            .commit()
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> = buildMap {
        put("id", json.optString("id"))
        put("title", json.optString("title", "Shared item"))
        put("text", json.optString("text", ""))
        put("createdAt", json.optLong("createdAt", 0L))
        put("files", jsonArrayToMaps(json.optJSONArray("files")))
        put("rejected", jsonArrayToMaps(json.optJSONArray("rejected")))
    }

    private fun jsonArrayToMaps(array: JSONArray?): List<Map<String, Any?>> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            array.optJSONObject(index)?.let { item ->
                buildMap {
                    for (key in item.keys()) put(key, item.opt(key))
                }
            }
        }
    }
}
