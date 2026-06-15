package com.example.n_queens_solver

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * Invisible trampoline Activity used exclusively by ScreenshotSolverTileService.
 *
 * Why this exists:
 * ─────────────────────────────────────────────────────────────────────────────
 * When the user taps the Quick Settings tile, the system calls TileService.onClick()
 * while the notification panel is still fully open on screen.
 *
 * We need to:
 *   1. Dismiss the panel — guaranteed by startActivityAndCollapse().
 *   2. Wait for the panel animation to finish (~350–500 ms).
 *   3. Only THEN trigger the capture so the screenshot shows the real app
 *      content, not the Quick Settings panel.
 *
 * This Activity sends ACTION_CAPTURE to the already-running
 * ProjectionSessionService. The session service holds the live MediaProjection
 * object, so no consent dialog is ever shown again after the initial grant.
 */
class CaptureTrampoline : Activity() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // No setContentView — window is transparent / zero-size
    }

    override fun onResume() {
        super.onResume()
        // onResume fires after the panel has fully collapsed.
        // Add a small buffer for the panel dismiss animation on slow OEM skins.
        handler.postDelayed({
            sendCaptureCommand()
            finish()
        }, PANEL_DISMISS_BUFFER_MS)
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacksAndMessages(null)
    }

    private fun sendCaptureCommand() {
        // ProjectionSessionService is already running (started in onActivityResult
        // when the user first granted MediaProjection). We just send it a capture
        // command — no new dialog appears because the live projection is reused.
        val intent = Intent(this, ProjectionSessionService::class.java).apply {
            action = ProjectionSessionService.ACTION_CAPTURE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        // Panel close animation is ~300 ms on stock Android, ~450 ms on some OEMs.
        // 500 ms is a safe buffer that covers all devices without feeling sluggish.
        private const val PANEL_DISMISS_BUFFER_MS = 500L
    }
}
