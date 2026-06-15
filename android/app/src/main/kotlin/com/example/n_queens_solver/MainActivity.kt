package com.example.n_queens_solver

import android.app.Activity
import android.content.*
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    // ── Channel names (must match Dart side) ─────────────────────────────────
    private val METHOD_CHANNEL  = "com.example.n_queens_solver/screenshot_solver"
    private val EVENT_CHANNEL   = "com.example.n_queens_solver/board_results"

    // ── Request codes ─────────────────────────────────────────────────────────
    private val REQ_MEDIA_PROJECTION = 1001
    private val REQ_OVERLAY_PERMISSION = 1002

    // ── EventChannel sink (streams board results to Flutter) ─────────────────
    private var boardResultSink: EventChannel.EventSink? = null

    // ── BroadcastReceiver from ScreenshotOverlayService ───────────────────────
    private val boardResultReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val boardJson = intent?.getStringExtra(ScreenshotOverlayService.EXTRA_BOARD_JSON) ?: return
            boardResultSink?.success(boardJson)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FlutterEngine configuration
    // ─────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel ────────────────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "requestMediaProjection" -> {
                    requestMediaProjectionPermission(result)
                }

                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }

                "hasOverlayPermission" -> {
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this)
                        else true
                    )
                }

                "hasMediaProjectionPermission" -> {
                    val prefs = getSharedPreferences(ScreenshotSolverTileService.PREFS_NAME, Context.MODE_PRIVATE)
                    val has = prefs.getInt(ScreenshotSolverTileService.KEY_PROJECTION_RESULT_CODE, -999) != -999
                    result.success(has)
                }

                "showSolvedOverlay" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any> ?: run {
                        result.error("INVALID_ARGS", "Expected Map arguments", null)
                        return@setMethodCallHandler
                    }
                    showSolvedOverlay(args)
                    result.success(null)
                }

                "dismissOverlay" -> {
                    OverlayWindow.dismiss()
                    result.success(null)
                }

                "isOverlayVisible" -> {
                    result.success(OverlayWindow.isVisible)
                }

                "isSessionAlive" -> {
                    // True only when ProjectionSessionService is actually running
                    // (not just a stale pref). ActivityManager lets us check.
                    val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                    @Suppress("DEPRECATION")
                    val running = am.getRunningServices(Int.MAX_VALUE)
                        ?.any { it.service.className == ProjectionSessionService::class.java.name }
                        ?: false
                    result.success(running)
                }

                "dismissLoadingOverlay" -> {
                    // Called by Flutter after it finishes solving (or fails),
                    // so the native loading spinner is cleaned up even if Flutter
                    // decides not to show the overlay (e.g. no solution).
                    ProjectionSessionService.dismissLoadingOverlayStatic()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        // ── EventChannel ─────────────────────────────────────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                boardResultSink = events
            }
            override fun onCancel(arguments: Any?) {
                boardResultSink = null
            }
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Activity lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerBoardResultReceiver()
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingIntent(intent)
    }

    override fun onDestroy() {
        unregisterReceiver(boardResultReceiver)
        super.onDestroy()
    }

    private fun registerBoardResultReceiver() {
        val filter = IntentFilter(ScreenshotOverlayService.ACTION_BOARD_RESULT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(boardResultReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(boardResultReceiver, filter)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Handle intents from TileService
    // ─────────────────────────────────────────────────────────────────────────

    private var pendingProjectionResult: MethodChannel.Result? = null

    private fun handleIncomingIntent(intent: Intent?) {
        when (intent?.action) {
            ScreenshotSolverTileService.ACTION_REQUEST_PROJECTION -> {
                requestMediaProjectionPermission(null)
            }
            ScreenshotSolverTileService.ACTION_REQUEST_OVERLAY -> {
                requestOverlayPermission()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MediaProjection permission
    // ─────────────────────────────────────────────────────────────────────────

    private fun requestMediaProjectionPermission(result: MethodChannel.Result?) {
        pendingProjectionResult = result
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), REQ_MEDIA_PROJECTION)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Overlay (SYSTEM_ALERT_WINDOW) permission
    // ─────────────────────────────────────────────────────────────────────────

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            // Primary intent: deep-link directly into the app-specific overlay setting.
            // This works on stock Android and most OEMs.
            val primaryIntent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            // Fallback: open the general "Display over other apps" list.
            // Some OEM skins (Samsung One UI, MIUI, ColorOS) do not honour the
            // package URI and just show an empty screen — the generic list always works.
            val fallbackIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)

            try {
                if (primaryIntent.resolveActivity(packageManager) != null) {
                    startActivityForResult(primaryIntent, REQ_OVERLAY_PERMISSION)
                } else {
                    startActivityForResult(fallbackIntent, REQ_OVERLAY_PERMISSION)
                }
            } catch (e: Exception) {
                // Last resort: open full app settings page
                try {
                    val appSettingsIntent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName")
                    )
                    startActivityForResult(appSettingsIntent, REQ_OVERLAY_PERMISSION)
                } catch (_: Exception) {}
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // onActivityResult
    // ─────────────────────────────────────────────────────────────────────────

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            REQ_MEDIA_PROJECTION -> {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    // ── Start the persistent session service RIGHT NOW, while the
                    //    token is still fresh. getMediaProjection() is called inside
                    //    the service constructor — this is the only call that matters.
                    //    All subsequent tile taps reuse the live MediaProjection object
                    //    inside the service, so the OS consent dialog never appears again.
                    val sessionIntent = Intent(this, ProjectionSessionService::class.java).apply {
                        putExtra(ProjectionSessionService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ProjectionSessionService.EXTRA_PROJECTION_DATA, data)
                        // No action = initial start
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(sessionIntent)
                    } else {
                        startService(sessionIntent)
                    }

                    // Also persist a flag so the tile knows permission was granted
                    // (we no longer store the raw token — the service owns the projection)
                    val prefs = getSharedPreferences(
                        ScreenshotSolverTileService.PREFS_NAME, Context.MODE_PRIVATE
                    )
                    prefs.edit()
                        .putInt(ScreenshotSolverTileService.KEY_PROJECTION_RESULT_CODE, resultCode)
                        .remove(ScreenshotSolverTileService.KEY_PROJECTION_DATA)  // not needed anymore
                        .apply()

                    pendingProjectionResult?.success(true)
                } else {
                    pendingProjectionResult?.success(false)
                }
                pendingProjectionResult = null
            }

            REQ_OVERLAY_PERMISSION -> {
                // Nothing special — the tile will retry on next tap
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Show solved overlay (called from Flutter via MethodChannel)
    // ─────────────────────────────────────────────────────────────────────────

    private fun showSolvedOverlay(args: Map<String, Any>) {
        val size = args["size"] as? Int ?: return
        @Suppress("UNCHECKED_CAST")
        val regionIdsRaw = args["regionIds"] as? List<List<Int>> ?: return
        @Suppress("UNCHECKED_CAST")
        val solutionRaw = args["solution"] as? Map<String, List<Int>>
        val failReason  = args["failReason"] as? String

        val solution: Map<Int, Pair<Int, Int>>? = solutionRaw?.entries?.associate { (k, v) ->
            k.toInt() to Pair(v[0], v[1])
        }

        // Dismiss native loading spinner before showing the result overlay
        ProjectionSessionService.dismissLoadingOverlayStatic()

        OverlayWindow.show(
            applicationContext,
            size,
            regionIdsRaw,
            solution,
            failReason
        )
    }
}
