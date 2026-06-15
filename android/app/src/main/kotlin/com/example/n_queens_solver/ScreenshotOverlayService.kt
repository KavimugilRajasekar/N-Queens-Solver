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
import android.util.DisplayMetrics
import android.view.*
import android.view.WindowManager
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
 * Foreground service that:
 *  1. Reads the stored MediaProjection token from SharedPreferences.
 *  2. Captures the screen via ImageReader + VirtualDisplay.
 *  3. Saves the screenshot to a temp file and POSTs it to /process-image.
 *  4. Parses the board, solves it natively (no Flutter needed), then shows
 *     OverlayWindow directly — this works even when the Flutter app is
 *     backgrounded or not running.
 *  5. Also broadcasts the board JSON to Flutter (if alive) via ACTION_BOARD_RESULT
 *     so the app can save it to the library.
 *  6. On failure / unrecognised board → shows a Toast.
 */
class ScreenshotOverlayService : Service() {

    private val CHANNEL_ID = "nq_solver_channel"
    private val NOTIF_ID = 1001

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
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
        // If an overlay is already visible, dismiss it first so the user
        // can tap the tile again to capture and solve a new board.
        if (OverlayWindow.isVisible) {
            OverlayWindow.dismiss()
        }

        // startForeground must happen within 5 seconds on all supported API levels.
        startForeground(NOTIF_ID, buildNotification("Capturing screen…"))

        // CaptureTrampoline already waited for the panel to fully dismiss.
        performCapture()

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Screen capture
    // ─────────────────────────────────────────────────────────────────────────

    private fun performCapture() {
        val prefs = getSharedPreferences(ScreenshotSolverTileService.PREFS_NAME, Context.MODE_PRIVATE)
        val resultCode = prefs.getInt(ScreenshotSolverTileService.KEY_PROJECTION_RESULT_CODE, Activity.RESULT_CANCELED)

        val dataString = prefs.getString(ScreenshotSolverTileService.KEY_PROJECTION_DATA, null)
        if (dataString == null || resultCode == Activity.RESULT_CANCELED) {
            showToast("Screen capture permission not granted. Tap the tile again.")
            stopSelf()
            return
        }

        val projectionData: Intent = try {
            Intent.parseUri(dataString, Intent.URI_INTENT_SCHEME)
        } catch (e: Exception) {
            showToast("Permission expired. Please re-authorize from the app.")
            clearProjectionPrefs(prefs)
            stopSelf()
            return
        }

        val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        val projection = try {
            projectionManager.getMediaProjection(resultCode, projectionData)
        } catch (e: Exception) {
            showToast("Screen capture unavailable. Please re-authorize.")
            clearProjectionPrefs(prefs)
            stopSelf()
            return
        }

        if (projection == null) {
            showToast("Could not start screen capture. Try again.")
            stopSelf()
            return
        }

        mediaProjection = projection

        // Android 14+ requires registering a callback before creating a VirtualDisplay
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    mainHandler.post {
                        cleanupCapture()
                        stopSelf()
                    }
                }
            }, mainHandler)
        }

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

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        virtualDisplay = projection.createVirtualDisplay(
            "nq_solver_capture",
            width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, null
        )

        // 300 ms gives VirtualDisplay time to render its first complete frame
        mainHandler.postDelayed({ acquireAndProcess(width, height) }, 300)
    }

    private fun acquireAndProcess(width: Int, height: Int) {
        val image = try {
            imageReader?.acquireLatestImage()
        } catch (e: Exception) {
            showToast("Screen capture failed. Try again.")
            cleanupCapture()
            stopSelf()
            return
        }
        if (image == null) {
            showToast("Screen capture failed. Try again.")
            cleanupCapture()
            stopSelf()
            return
        }

        val bitmap = try {
            val planes = image.planes
            if (planes.isEmpty()) {
                image.close()
                cleanupCapture()
                stopSelf()
                showToast("Screen capture failed. Try again.")
                return
            }
            val buffer      = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride   = planes[0].rowStride
            val rowPadding  = maxOf(0, rowStride - pixelStride * width)
            val bitmapWidth = width + if (pixelStride > 0) rowPadding / pixelStride else 0

            val raw = Bitmap.createBitmap(
                maxOf(bitmapWidth, width), height, Bitmap.Config.ARGB_8888
            )
            raw.copyPixelsFromBuffer(buffer)
            image.close()

            if (raw.width > width) {
                val cropped = Bitmap.createBitmap(raw, 0, 0, width, height)
                raw.recycle()
                cropped
            } else {
                raw
            }
        } catch (e: Exception) {
            try { image.close() } catch (_: Exception) {}
            cleanupCapture()
            stopSelf()
            showToast("Screen capture failed. Try again.")
            return
        }

        cleanupCapture()

        // Show loading indicator, then upload
        mainHandler.post { showLoadingOverlay() }

        scope.launch {
            uploadAndProcess(bitmap)
        }
    }

    private fun cleanupCapture() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Upload to /process-image
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
                    "file",
                    tempFile.name,
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
                    showToast("Server error (${response.code}). Could not process screenshot.")
                    stopSelf()
                }
                return
            }

            val boardJson = parseBoardResponse(responseBody)
            if (boardJson == null) {
                mainHandler.post {
                    dismissLoadingOverlay()
                    showToast("Unable to detect a valid N-Queens board in this screenshot.")
                    stopSelf()
                }
                return
            }

            // ── Solve the board natively (no Flutter engine required) ─────────
            val size = boardJson.getInt("size")
            val regionIdsJson = boardJson.getJSONArray("regionIds")
            val regionIds = List(size) { r ->
                List(size) { c -> regionIdsJson.getJSONArray(r).getInt(c) }
            }

            val solution: Map<Int, Pair<Int, Int>>? = solveBoard(size, regionIds)

            mainHandler.post {
                dismissLoadingOverlay()

                if (solution == null) {
                    showToast("Board detected but no solution found.")
                    stopSelf()
                    return@post
                }

                // ── Show solved overlay immediately (works even when Flutter is dead)
                OverlayWindow.show(applicationContext, size, regionIds, solution)

                // ── Also notify Flutter (if alive) so it can save to library ──
                broadcastBoardResult(boardJson, responseBody)

                stopSelf()
            }

        } catch (e: java.net.UnknownHostException) {
            mainHandler.post {
                dismissLoadingOverlay()
                showToast("No internet connection. Check your network and try again.")
                stopSelf()
            }
        } catch (e: java.net.SocketTimeoutException) {
            mainHandler.post {
                dismissLoadingOverlay()
                showToast("Server timed out. Try again in a moment.")
                stopSelf()
            }
        } catch (e: Exception) {
            mainHandler.post {
                dismissLoadingOverlay()
                showToast("Upload failed: ${e.message?.take(80)}")
                stopSelf()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Native N-Queens solver (backtracking, matches Dart solver logic)
    //
    // Rules:
    //   • Exactly one queen per row.
    //   • Exactly one queen per column.
    //   • Exactly one queen per diagonal (both directions).
    //   • Exactly one queen per region (colour zone).
    // ─────────────────────────────────────────────────────────────────────────

    private fun solveBoard(size: Int, regionIds: List<List<Int>>): Map<Int, Pair<Int, Int>>? {
        // solution[row] = col (0-based)
        val solution = IntArray(size) { -1 }

        // Find the actual max region ID to avoid ArrayIndexOutOfBoundsException
        var maxRegion = size
        for (row in regionIds) {
            for (id in row) {
                if (id > maxRegion) maxRegion = id
            }
        }

        val usedCols    = BooleanArray(size)
        val usedRegions = BooleanArray(maxRegion + 1)  // safe for any region ID

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

        // Build regionId → (1-based row, 1-based col)
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
    // Board parsing (same logic as before)
    // ─────────────────────────────────────────────────────────────────────────

    private fun parseBoardResponse(body: String): JSONObject? {
        val regionRegex = Regex("""Q(\d+)\s*[:=]\s*\[(.*?)\]""", RegexOption.IGNORE_CASE)
        val pointRegex  = Regex("""\((\d+)\s*,\s*(\d+)\)""")

        val regionMap = mutableMapOf<Int, MutableList<Pair<Int, Int>>>()
        for (match in regionRegex.findAll(body)) {
            val id = match.groupValues[1].toIntOrNull() ?: continue
            val coordsStr = match.groupValues[2]
            val coords = mutableListOf<Pair<Int, Int>>()
            for (pm in pointRegex.findAll(coordsStr)) {
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
                    val idMatch = Regex("""Q(\d+)""", RegexOption.IGNORE_CASE).find(key)
                    val id = idMatch?.groupValues?.get(1)?.toIntOrNull() ?: return@forEach
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
        for (coords in regionMap.values) {
            for ((x, y) in coords) {
                if (x > maxVal) maxVal = x
                if (y > maxVal) maxVal = y
            }
        }
        val n = if (maxVal > 0) minOf(maxVal, 12) else return null
        if (n < 4) return null

        val regionIds = Array(n) { IntArray(n) }
        val sortedKeys = regionMap.keys.sorted()
        var normalizedId = 1
        val idMapping = mutableMapOf<Int, Int>()
        for (origId in sortedKeys) {
            idMapping[origId] = normalizedId++
        }

        for ((origId, coords) in regionMap) {
            val mappedId = idMapping[origId] ?: continue
            for ((x, y) in coords) {
                val row = x - 1
                val col = y - 1
                if (row in 0 until n && col in 0 until n) {
                    regionIds[row][col] = mappedId
                }
            }
        }

        for (row in regionIds) {
            for (cell in row) {
                if (cell == 0) return null
            }
        }

        val result = JSONObject()
        result.put("size", n)
        result.put("rawResponse", body)

        val regionIdsJson = org.json.JSONArray()
        for (row in regionIds) {
            val rowArr = org.json.JSONArray()
            for (cell in row) rowArr.put(cell)
            regionIdsJson.put(rowArr)
        }
        result.put("regionIds", regionIdsJson)

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
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = 200
        }

        val tv = android.widget.TextView(this).apply {
            text = "⏳ Analyzing board..."
            textSize = 16f
            setTextColor(Color.parseColor("#3F51B5"))
            setBackgroundResource(android.R.drawable.toast_frame)
            setPadding(32, 16, 32, 16)
        }
        loadingView = tv
        try { wm.addView(tv, params) } catch (_: Exception) {}
    }

    private fun dismissLoadingOverlay() {
        loadingView?.let {
            try {
                val wm = getSystemService(WINDOW_SERVICE) as WindowManager
                wm.removeView(it)
            } catch (_: Exception) {}
            loadingView = null
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Broadcast result to Flutter (optional — saves to library if app is alive)
    // ─────────────────────────────────────────────────────────────────────────

    private fun broadcastBoardResult(boardJson: JSONObject, rawResponse: String) {
        val intent = Intent(ACTION_BOARD_RESULT).apply {
            putExtra(EXTRA_BOARD_JSON, boardJson.toString())
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private fun clearProjectionPrefs(prefs: android.content.SharedPreferences) {
        prefs.edit()
            .remove(ScreenshotSolverTileService.KEY_PROJECTION_RESULT_CODE)
            .remove(ScreenshotSolverTileService.KEY_PROJECTION_DATA)
            .apply()
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "N-Queens Screenshot Solver",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Used for screenshot capture notifications"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("N-Queens Solver")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_BOARD_RESULT = "com.example.n_queens_solver.BOARD_RESULT"
        const val EXTRA_BOARD_JSON    = "board_json"
    }
}
