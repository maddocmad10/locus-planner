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
                if (manifest == null) {
                    dir.deleteRecursively()
                    return@execute
                }
                writeManifest(dir, manifest)
                addPending(app, id)
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
        var accepted = 0
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
                        .put("reason", "too_many_files"),
                )
                continue
            }
            val safe = name
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
                .take(80)
                .ifBlank { "shared" }
            val target = File(dir, "$ordinal-$safe")
            val bytes = copyWithLimit(context, uri, target)
            if (bytes == null) {
                target.delete()
                rejected.put(
                    JSONObject()
                        .put("name", name)
                        .put("mimeType", mime)
                        .put("reason", "unreadable_or_over_limit"),
                )
                continue
            }
            accepted++
            files.put(
                JSONObject()
                    .put("path", target.absolutePath)
                    .put("name", name)
                    .put("mimeType", mime)
                    .put("bytes", bytes)
                    // Deterministic per-intake mapping; replaying the intake
                    // reuses the same attachment id.
                    .put("attachmentId", "$id-$ordinal"),
            )
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
            files.length() > 0 -> "Shared file"
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

    private fun copyWithLimit(context: Context, uri: Uri, target: File): Long? {
        return try {
            context.contentResolver.openInputStream(uri)?.use { source ->
                target.outputStream().use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_FILE_BYTES) return null
                        sink.write(buffer, 0, read)
                    }
                    total
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    fun take(context: Context): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        for (id in pendingIds(context)) {
            val file = File(context.cacheDir, "share_intake/$id/manifest.json")
            if (!file.isFile) continue
            try {
                result.add(jsonToMap(JSONObject(file.readText())))
            } catch (_: Exception) {
                // A damaged manifest is skipped; its directory is swept later.
            }
        }
        return result
    }

    /// Marks the intake complete before removing staged files. A crash after
    /// the task commit but before this call replays safely because Dart reuses
    /// the intake id as the task id.
    fun complete(context: Context, id: String) {
        val dir = File(context.cacheDir, "share_intake/$id")
        try {
            val manifest = File(dir, "manifest.json")
            if (manifest.isFile) {
                val json = JSONObject(manifest.readText()).put("complete", true)
                manifest.writeText(json.toString())
            }
        } catch (_: Exception) {
            // Best effort; the sweep removes old directories anyway.
        }
        dir.deleteRecursively()
        removePending(context, id)
    }

    fun sweep(context: Context) {
        val root = File(context.cacheDir, "share_intake")
        if (!root.isDirectory) return
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        root.listFiles()?.forEach { dir ->
            if (!dir.isDirectory) return@forEach
            val manifest = File(dir, "manifest.json")
            val keep = manifest.isFile && manifest.lastModified() >= cutoff
            if (!keep) dir.deleteRecursively()
        }
    }

    private fun writeManifest(dir: File, manifest: JSONObject) {
        File(dir, "manifest.json").writeText(manifest.toString())
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

    private fun addPending(context: Context, id: String) {
        val ids = pendingIds(context).toMutableList()
        ids.add(id)
        while (ids.size > MAX_PENDING) ids.removeAt(0)
        savePending(context, ids)
    }

    private fun removePending(context: Context, id: String) {
        val ids = pendingIds(context).toMutableList()
        ids.remove(id)
        savePending(context, ids)
    }

    private fun savePending(context: Context, ids: List<String>) {
        val array = JSONArray()
        ids.forEach(array::put)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
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
