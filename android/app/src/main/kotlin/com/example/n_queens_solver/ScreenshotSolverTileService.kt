package com.example.n_queens_solver

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.View
import android.view.WindowManager
import android.graphics.PixelFormat
import androidx.annotation.RequiresApi

/**
 * Quick Settings Tile that captures the screen and triggers the solver pipeline.
 */
@RequiresApi(Build.VERSION_CODES.N)
class ScreenshotSolverTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hasProjectionPermission = prefs.getInt(KEY_PROJECTION_RESULT_CODE, -999) != -999
        val isSessionAlive = ProjectionSessionService.isSessionAlive
        val hasOverlay = canDrawOverlaysRobust(this)

        if (!hasProjectionPermission || !isSessionAlive || !hasOverlay) {
            // Open the app directly to the Quick Access screen
            val intent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_SHOW_QUICK_ACCESS
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            collapseAndLaunch(intent)
            return
        }

        // All permissions granted — launch transparent CaptureTrampoline.
        val intent = Intent(this, CaptureTrampoline::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
        }
        collapseAndLaunch(intent)
    }

    private fun collapseAndLaunch(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pi = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileState() {
        qsTile?.apply {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val hasProjectionPermission = prefs.getInt(KEY_PROJECTION_RESULT_CODE, -999) != -999
            val isSessionAlive = ProjectionSessionService.isSessionAlive
            val hasOverlay = canDrawOverlaysRobust(this@ScreenshotSolverTileService)

            if (hasProjectionPermission && isSessionAlive && hasOverlay) {
                state = Tile.STATE_ACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    subtitle = "Tap to solve"
                }
            } else {
                state = Tile.STATE_INACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    subtitle = "Deactivated"
                }
            }
            label = "NQ-Quick Scan"
            icon = android.graphics.drawable.Icon.createWithResource(
                this@ScreenshotSolverTileService,
                R.drawable.ic_qs_tile
            )
            updateTile()
        }
    }

    companion object {
        const val PREFS_NAME = "nq_solver_prefs"
        const val KEY_PROJECTION_RESULT_CODE = "projection_result_code"
        const val KEY_PROJECTION_DATA = "projection_data"
        const val ACTION_REQUEST_PROJECTION = "com.example.n_queens_solver.REQUEST_PROJECTION"
        const val ACTION_REQUEST_OVERLAY = "com.example.n_queens_solver.ACTION_REQUEST_OVERLAY"
        const val ACTION_CLOSE_APP = "com.example.n_queens_solver.ACTION_CLOSE_APP"
        const val ACTION_SHOW_QUICK_ACCESS = "com.example.n_queens_solver.ACTION_SHOW_QUICK_ACCESS"

        fun canDrawOverlaysRobust(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
            if (!Settings.canDrawOverlays(context)) return false
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return false
            val view = View(context)
            val params = WindowManager.LayoutParams(
                0, 0,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSPARENT
            )
            return try {
                wm.addView(view, params)
                wm.removeView(view)
                true
            } catch (e: Exception) {
                android.util.Log.e("OverlayCheck", "canDrawOverlays was true but addView failed: ${e.message}")
                false
            }
        }
    }
}
