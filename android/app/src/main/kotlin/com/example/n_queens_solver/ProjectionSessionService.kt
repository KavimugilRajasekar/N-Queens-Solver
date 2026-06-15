package com.example.n_queens_solver

import android.app.*
import android.content.*
import android.graphics.*
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import android.service.quicksettings.TileService
import android.util.DisplayMetrics
import android.view.*
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.*
import java.util.concurrent.TimeUnit

/**
 * Persistent foreground service that holds an active [MediaProjection] session.
 *
 * WHY THIS EXISTS
 * ───────────────
 * Android's MediaProjection token (the resultCode + Intent from onActivityResult)
 * is single-use on Android 10+. Calling getMediaProjection() with a saved/replayed
 * token causes the OS to show the "Start recording or casting?" consent dialog again
 * on every tile tap.
 *
 * The only way to avoid the dialog is to:
 *   1. Call getMediaProjection() ONCE while the token is fresh (in onActivityResult).
 *   2. Keep the resulting MediaProjection object alive in a long-running service.
 *   3. Reuse that same live object for every subsequent capture.
 *
 * LIFECYCLE
 * ─────────
 *   • Started by MainActivity right after the user grants MediaProjection (fresh token).
 *   • Stays running silently with a low-priority persistent notification.
 *   • On ACTION_CAPTURE: takes a screenshot, uploads it, solves and shows overlay.
 *   • On ACTION_STOP or when the user revokes permission: stops itself and clears prefs.
 *
 * CAPTURE FLOW
 * ────────────
 *   TileService → CaptureTrampoline (500 ms wait) → ACTION_CAPTURE intent →
 *   ProjectionSessionService → VirtualDisplay → ImageReader → bitmap →
 *   OkHttp POST /process-image → parse → solve (native) → OverlayWindow.show()
 */
class ProjectionSessionService : Service() {

    companion object {
        const val ACTION_CAPTURE = "com.example.n_queens_solver.ACTION_CAPTURE"
        const val ACTION_STOP    = "com.example.n_queens_solver.ACTION_STOP"

        // Extras carried on the start intent when creating the projection for the first time
        const val EXTRA_RESULT_CODE    = "result_code"
        const val EXTRA_PROJECTION_DATA = "projection_data"

        private const val CHANNEL_ID = "nq_session_channel"
        private const val NOTIF_ID   = 1002

        // Traces if a valid MediaProjection session is currently running
        @Volatile var isSessionAlive = false

        // Held statically so MainActivity can dismiss it on the main thread
        // when Flutter calls back with a solve result.
        @Volatile private var loadingViewStatic: android.widget.TextView? = null
        @Volatile private var wmStatic: WindowManager? = null

        fun dismissLoadingOverlayStatic() {
            val v  = loadingViewStatic ?: return
            val wm = wmStatic          ?: return
            try { wm.removeView(v) } catch (_: Exception) {}
            loadingViewStatic = null
            wmStatic          = null
        }
    }

    // ── live projection objects ───────────────────────────────────────────────
    private var mediaProjection: MediaProjection? = null

    // ── reusable capture resources (recreated per capture) ───────────────────
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var isCaptureInProgress = false

    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == null) {
            // First-time start: promote to foreground using mediaProjection type (required on Android 14+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    buildNotification("NQ Solver ready"),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIF_ID, buildNotification("NQ Solver ready"))
            }

            val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                ?: Activity.RESULT_CANCELED
            val projectionData = intent?.getParcelableExtra<Intent>(EXTRA_PROJECTION_DATA)

            if (resultCode != Activity.RESULT_OK || projectionData == null) {
                isSessionAlive = false
                updateTileStateQuietly()
                stopSelf()
                return START_NOT_STICKY
            }
            initProjection(resultCode, projectionData)
        } else {
            when (action) {
                // ── Stop request ───────────────────────────────────────────────────
                ACTION_STOP -> {
                    isSessionAlive = false
                    updateTileStateQuietly()
                    stopSelf()
                    return START_NOT_STICKY
                }

                // ── Tile was tapped: take a screenshot now ────────────────────────
                ACTION_CAPTURE -> {
                    if (mediaProjection == null) {
                        // Session died (e.g. phone restarted) — clear stale prefs and
                        // ask the user to re-grant from the app.
                        isSessionAlive = false
                        clearProjectionPrefs()
                        updateTileStateQuietly()
                        showToast("Session expired. Open N-Queens app to re-authorize.")
                        stopSelf()
                        return START_NOT_STICKY
                    }

                    if (isCaptureInProgress) {
                        showToast("Already capturing, please wait…")
                        return START_NOT_STICKY
                    }

                    // Dismiss any previously visible overlay before taking a new shot
                    if (OverlayWindow.isVisible) {
                        mainHandler.post { OverlayWindow.dismiss() }
                    }
                    performCapture()
                }
            }
        }

        // START_NOT_STICKY: if the OS kills this service (e.g. memory pressure),
        // do NOT restart it with a null intent — that would try to re-init with no
        // token and immediately stop itself, clearing a valid projection session.
        // The user can simply tap the tile again to trigger a new session start.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        releaseCapture()
        mediaProjection?.stop()
        mediaProjection = null
        isSessionAlive = false
        updateTileStateQuietly()
        super.onDestroy()
    }

    private fun updateTileStateQuietly() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                TileService.requestListeningState(
                    applicationContext,
                    ComponentName(applicationContext, ScreenshotSolverTileService::class.java)
                )
            } catch (_: Exception) {}
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Projection initialisation (called exactly once per grant)
    // ─────────────────────────────────────────────────────────────────────────

    private fun initProjection(resultCode: Int, data: Intent) {
        // If a projection is already alive, stop it cleanly before replacing it
        if (mediaProjection != null) {
            mediaProjection?.stop()
            mediaProjection = null
        }

        val mgr = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = try {
            mgr.getMediaProjection(resultCode, data)
        } catch (e: Exception) {
            isSessionAlive = false
            clearProjectionPrefs()
            updateTileStateQuietly()
            stopSelf()
            return
        }
        if (projection == null) {
            isSessionAlive = false
            clearProjectionPrefs()
            updateTileStateQuietly()
            stopSelf()
            return
        }
        mediaProjection = projection
        isSessionAlive = true
        updateTileStateQuietly()

        // Android 14+: must register callback before creating a VirtualDisplay
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    // User or system revoked permission — clean up
                    mainHandler.post {
                        clearProjectionPrefs()
                        releaseCapture()
                        mediaProjection = null
                        isSessionAlive = false
                        updateTileStateQuietly()
                        stopSelf()
                    }
                }
            }, mainHandler)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Screen capture
    // ─────────────────────────────────────────────────────────────────────────

    private fun performCapture() {
        isCaptureInProgress = true
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val (width, height, dpi) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            Triple(bounds.width(), bounds.height(), resources.displayMetrics.densityDpi)
        } else {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getMetrics(metrics)
            Triple(metrics.widthPixels, metrics.heightPixels, metrics.densityDpi)
        }

        // Fresh ImageReader + VirtualDisplay for every capture
        releaseCapture()

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay = mediaProjection!!.createVirtualDisplay(
            "nq_capture",
            width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        // 300 ms for the VirtualDisplay to render its first complete frame
        mainHandler.postDelayed({ acquireFrame(width, height) }, 300)
    }

    private fun acquireFrame(width: Int, height: Int) {
        val image = try {
            imageReader?.acquireLatestImage()
        } catch (e: Exception) {
            releaseCapture()
            finishCapturePipeline()
            showToast("Screen capture failed. Try again.")
            return
        }
        if (image == null) {
            releaseCapture()
            finishCapturePipeline()
            showToast("Screen capture failed. Try again.")
            return
        }

        val bitmap = try {
            val planes = image.planes
            if (planes.isEmpty()) {
                image.close()
                releaseCapture()
                finishCapturePipeline()
                showToast("Screen capture failed. Try again.")
                return
            }
            val buffer      = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride   = planes[0].rowStride
            // rowPadding can be 0 or negative on some devices/formats — clamp to 0
            val rowPadding  = maxOf(0, rowStride - pixelStride * width)
            val bitmapWidth = width + if (pixelStride > 0) rowPadding / pixelStride else 0

            val raw = Bitmap.createBitmap(
                maxOf(bitmapWidth, width), height, Bitmap.Config.ARGB_8888
            )
            raw.copyPixelsFromBuffer(buffer)
            image.close()

            // Crop to exact screen dimensions, discarding any row-padding columns
            if (raw.width > width) {
                val cropped = Bitmap.createBitmap(raw, 0, 0, width, height)
                raw.recycle()
                cropped
            } else {
                raw
            }
        } catch (e: Exception) {
            try { image.close() } catch (_: Exception) {}
            releaseCapture()
            finishCapturePipeline()
            showToast("Screen capture failed. Try again.")
            return
        }

        releaseCapture()

        // Terminate the MediaProjection session immediately since the token has been used
        mediaProjection?.stop()
        mediaProjection = null
        isSessionAlive = false
        clearProjectionPrefs()
        updateTileStateQuietly()

        mainHandler.post { showLoadingOverlay() }
        scope.launch { uploadAndProcess(bitmap) }
    }

    private fun releaseCapture() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        // NOTE: do NOT stop mediaProjection here — we keep it alive for reuse
        // isCaptureInProgress is reset by finishCapturePipeline() after upload completes
    }

    /** Must be called on the main thread after the full pipeline (upload + overlay) finishes. */
    private fun finishCapturePipeline() {
        isCaptureInProgress = false
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Upload → parse → solve → show overlay
    // ─────────────────────────────────────────────────────────────────────────

    private suspend fun uploadAndProcess(bitmap: Bitmap) {
        try {
            val tempFile = File(cacheDir, "nq_screenshot_${System.currentTimeMillis()}.jpg")
            FileOutputStream(tempFile).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 90, fos)
            }
            bitmap.recycle()

            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "file", tempFile.name,
                    tempFile.readBytes().toRequestBody("image/jpeg".toMediaTypeOrNull())
                )
                .build()

            val request = Request.Builder()
                .url("https://nqueensserver.vercel.app/process-image")
                .post(requestBody)
                .build()

            val response: Response = httpClient.newCall(request).execute()
            val responseBody = response.body?.string() ?: ""
            tempFile.delete()

            if (!response.isSuccessful) {
                mainHandler.post {
                    dismissLoadingOverlay()
                    finishCapturePipeline()
                    showToast("Server error (${response.code}). Could not process screenshot.")
                    stopSelf()
                }
                return
            }

            val boardJson = parseBoardResponse(responseBody)
            if (boardJson == null) {
                mainHandler.post {
                    dismissLoadingOverlay()
                    finishCapturePipeline()
                    showToast("No N-Queens board detected in screenshot.")
                    stopSelf()
                }
                return
            }

            // ── Solve the board natively (works even when Flutter is dead) ──
            val size = boardJson.getInt("size")
            val regionIdsJson = boardJson.getJSONArray("regionIds")
            val regionIds = List(size) { r ->
                List(size) { c -> regionIdsJson.getJSONArray(r).getInt(c) }
            }

            // --- VALIDATION STARTS ---
            var failReason: String? = null

            // 1. Verify region count matches size
            val uniqueRegions = mutableSetOf<Int>()
            for (row in regionIds) {
                for (id in row) {
                    uniqueRegions.add(id)
                }
            }
            if (uniqueRegions.size != size) {
                failReason = "Expected $size regions for a ${size}x${size} board, but found ${uniqueRegions.size}. Please capture again."
            }

            // 2. Verify all regions are connected (no drifting cells)
            if (failReason == null) {
                val disconnected = mutableListOf<Int>()
                for (id in uniqueRegions) {
                    if (!isRegionConnected(size, regionIds, id)) {
                        disconnected.add(id)
                    }
                }
                if (disconnected.isNotEmpty()) {
                    failReason = "Region${if (disconnected.size > 1) "s" else ""} ${disconnected.joinToString(", ")} ${if (disconnected.size > 1) "contain" else "contains"} disconnected (drifting) cells. Please capture again."
                }
            }
            // --- VALIDATION ENDS ---

            val solution: Map<Int, Pair<Int, Int>>? = if (failReason == null) {
                solveBoard(size, regionIds)
            } else {
                null
            }

            mainHandler.post {
                dismissLoadingOverlay()
                finishCapturePipeline()

                if (solution == null) {
                    // Show unsolvable state on overlay
                    OverlayWindow.show(
                        applicationContext,
                        size,
                        regionIds,
                        null,
                        failReason ?: "No valid queen placement exists for this board."
                    )
                } else {
                    // Show solved overlay immediately
                    OverlayWindow.show(applicationContext, size, regionIds, solution)
                }

                // Also notify Flutter (if alive) so it can save to library
                broadcastBoardResult(boardJson)
                stopSelf()
            }

        } catch (e: java.net.UnknownHostException) {
            mainHandler.post { dismissLoadingOverlay(); finishCapturePipeline(); showToast("No internet connection."); stopSelf() }
        } catch (e: java.net.SocketTimeoutException) {
            mainHandler.post { dismissLoadingOverlay(); finishCapturePipeline(); showToast("Server timed out. Try again."); stopSelf() }
        } catch (e: Exception) {
            mainHandler.post { dismissLoadingOverlay(); finishCapturePipeline(); showToast("Error: ${e.message?.take(80)}"); stopSelf() }
        }
    }

    private fun isRegionConnected(size: Int, regionIds: List<List<Int>>, regionId: Int): Boolean {
        val coords = mutableListOf<Pair<Int, Int>>()
        for (r in 0 until size) {
            for (c in 0 until size) {
                if (regionIds[r][c] == regionId) {
                    coords.add(Pair(r, c))
                }
            }
        }
        if (coords.isEmpty()) return true

        val coordsSet = coords.map { "${it.first},${it.second}" }.toSet()
        val visited = mutableSetOf<String>()

        val queue = mutableListOf<Pair<Int, Int>>()
        queue.add(coords.first())
        visited.add("${coords.first().first},${coords.first().second}")

        var head = 0
        while (head < queue.size) {
            val current = queue[head++]
            val neighbors = listOf(
                Pair(current.first + 1, current.second),
                Pair(current.first - 1, current.second),
                Pair(current.first, current.second + 1),
                Pair(current.first, current.second - 1)
            )
            for (neighbor in neighbors) {
                val key = "${neighbor.first},${neighbor.second}"
                if (coordsSet.contains(key) && !visited.contains(key)) {
                    visited.add(key)
                    queue.add(neighbor)
                }
            }
        }

        return visited.size == coords.size
    }

    // ── Native solver logic matching solver_logic.dart ──
    private fun solveBoard(size: Int, regionIds: List<List<Int>>): Map<Int, Pair<Int, Int>>? {
        val solution = IntArray(size) { -1 }

        var maxRegion = size
        for (row in regionIds) {
            for (id in row) {
                if (id > maxRegion) maxRegion = id
            }
        }

        val usedCols    = BooleanArray(size)
        val usedRegions = BooleanArray(maxRegion + 1)

        fun bt(row: Int): Boolean {
            if (row == size) return true
            for (col in 0 until size) {
                val region = regionIds[row][col]
                if (region <= 0 || region > maxRegion) continue
                
                // Adjacency check: cannot touch the queen in the previous row
                if (row > 0) {
                    val prevCol = solution[row - 1]
                    if (Math.abs(col - prevCol) <= 1) continue
                }

                if (usedCols[col] || usedRegions[region]) continue
                
                solution[row] = col
                usedCols[col] = true
                usedRegions[region] = true
                
                if (bt(row + 1)) return true
                
                solution[row] = -1
                usedCols[col] = false
                usedRegions[region] = false
            }
            return false
        }

        if (!bt(0)) return null

        val result = mutableMapOf<Int, Pair<Int, Int>>()
        for (row in 0 until size) {
            val col = solution[row]
            if (col < 0) return null
            val region = regionIds[row][col]
            result[region] = Pair(row + 1, col + 1)
        }
        return result
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Board response parser
    // ─────────────────────────────────────────────────────────────────────────

    private fun parseBoardResponse(body: String): JSONObject? {
        val regionRegex = Regex("""Q(\d+)\s*[:=]\s*\[(.*?)\]""", RegexOption.IGNORE_CASE)
        val pointRegex  = Regex("""\((\d+)\s*,\s*(\d+)\)""")

        val regionMap = mutableMapOf<Int, MutableList<Pair<Int, Int>>>()
        for (match in regionRegex.findAll(body)) {
            val id = match.groupValues[1].toIntOrNull() ?: continue
            val coords = mutableListOf<Pair<Int, Int>>()
            for (pm in pointRegex.findAll(match.groupValues[2])) {
                val x = pm.groupValues[1].toIntOrNull() ?: continue
                val y = pm.groupValues[2].toIntOrNull() ?: continue
                coords.add(Pair(x, y))
            }
            regionMap[id] = coords
        }

        if (regionMap.isEmpty()) {
            try {
                val decoded = JSONObject(body)
                decoded.keys().forEach { key ->
                    val id = Regex("""Q(\d+)""", RegexOption.IGNORE_CASE)
                        .find(key)?.groupValues?.get(1)?.toIntOrNull() ?: return@forEach
                    val arr = decoded.optJSONArray(key) ?: return@forEach
                    val coords = mutableListOf<Pair<Int, Int>>()
                    for (i in 0 until arr.length()) {
                        val pt = arr.optJSONArray(i) ?: continue
                        coords.add(Pair(pt.optInt(0), pt.optInt(1)))
                    }
                    regionMap[id] = coords
                }
            } catch (_: Exception) {}
        }

        if (regionMap.isEmpty()) return null

        var maxVal = 0
        for (coords in regionMap.values) for ((x, y) in coords) { if (x > maxVal) maxVal = x; if (y > maxVal) maxVal = y }
        val n = if (maxVal > 0) minOf(maxVal, 12) else return null
        if (n < 4) return null

        val grid = Array(n) { IntArray(n) }
        val sortedKeys = regionMap.keys.sorted()
        val idMap = sortedKeys.mapIndexed { i, k -> k to (i + 1) }.toMap()
        for ((origId, coords) in regionMap) {
            val mapped = idMap[origId] ?: continue
            for ((x, y) in coords) {
                val r = x - 1; val c = y - 1
                if (r in 0 until n && c in 0 until n) grid[r][c] = mapped
            }
        }
        for (row in grid) for (cell in row) if (cell == 0) return null

        val result = JSONObject().apply { put("size", n); put("rawResponse", body) }
        val arr = org.json.JSONArray()
        for (row in grid) { val ra = org.json.JSONArray(); for (c in row) ra.put(c); arr.put(ra) }
        result.put("regionIds", arr)
        return result
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Loading overlay
    // ─────────────────────────────────────────────────────────────────────────

    private var loadingView: android.widget.TextView? = null

    private fun showLoadingOverlay() {
        if (loadingView != null) return
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL; y = 200 }

        val tv = android.widget.TextView(this).apply {
            text = "⏳ Analyzing board..."
            textSize = 16f
            setTextColor(Color.parseColor("#3F51B5"))
            setBackgroundResource(android.R.drawable.toast_frame)
            setPadding(32, 16, 32, 16)
        }
        loadingView = tv
        wmStatic    = wm
        loadingViewStatic = tv
        try { wm.addView(tv, params) } catch (_: Exception) {}
    }

    private fun dismissLoadingOverlay() {
        loadingView?.let {
            try { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it) } catch (_: Exception) {}
            loadingView = null
        }
        loadingViewStatic = null
        wmStatic          = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Broadcast to Flutter
    // ─────────────────────────────────────────────────────────────────────────

    private fun broadcastBoardResult(boardJson: JSONObject) {
        sendBroadcast(Intent(ScreenshotOverlayService.ACTION_BOARD_RESULT).apply {
            putExtra(ScreenshotOverlayService.EXTRA_BOARD_JSON, boardJson.toString())
            setPackage(packageName)
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun clearProjectionPrefs() {
        getSharedPreferences(ScreenshotSolverTileService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(ScreenshotSolverTileService.KEY_PROJECTION_RESULT_CODE)
            .remove(ScreenshotSolverTileService.KEY_PROJECTION_DATA)
            .apply()
    }

    private fun showToast(msg: String) {
        Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "NQ Solver Session", NotificationManager.IMPORTANCE_MIN
            ).apply { description = "Keeps screen capture session active" }
            (getSystemService(NotificationManager::class.java)).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("N-Queens Solver")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
}
