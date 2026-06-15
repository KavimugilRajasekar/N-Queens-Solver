package com.example.n_queens_solver

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings Tile that captures the screen and triggers the solver pipeline.
 *
 * Flow:
 *  1. User taps tile in notification shade.
 *  2a. If any permission is missing → launch MainActivity to request it.
 *  2b. All permissions granted → launch CaptureTrampoline via startActivityAndCollapse().
 *      startActivityAndCollapse() GUARANTEES the panel is dismissed before the
 *      Activity launches. CaptureTrampoline is fully transparent (invisible) and
 *      waits 500 ms for the dismiss animation to finish, then fires
 *      ACTION_CAPTURE on ProjectionSessionService and calls finish().
 *
 * Android 14+ (API 34): startActivityAndCollapse(Intent) is removed. Must use
 * startActivityAndCollapse(PendingIntent) instead to avoid crash + panel not closing.
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

        if (!hasProjectionPermission) {
            // Ask the main activity to request the MediaProjection permission.
            val intent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_REQUEST_PROJECTION
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            collapseAndLaunch(intent)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_REQUEST_OVERLAY
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            collapseAndLaunch(intent)
            return
        }

        // All permissions granted — launch transparent CaptureTrampoline.
        // Trampoline waits 500 ms for panel animation, then sends ACTION_CAPTURE
        // to ProjectionSessionService (which holds the live MediaProjection).
        // No consent dialog appears.
        val intent = Intent(this, CaptureTrampoline::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TASK or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
        }
        collapseAndLaunch(intent)
    }

    /**
     * Collapses the Quick Settings panel and launches [intent].
     *
     * On Android 14+ (API 34) the Intent overload of startActivityAndCollapse
     * was removed and throws UnsupportedOperationException, causing the crash
     * and the panel staying open. We must use the PendingIntent overload.
     *
     * On earlier APIs the Intent overload is still available, so we keep that
     * path to avoid the extra PendingIntent overhead.
     */
    private fun collapseAndLaunch(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // API 34+ — must use PendingIntent overload
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
            state = Tile.STATE_ACTIVE
            label = "NQ Solver"
            icon = android.graphics.drawable.Icon.createWithResource(
                this@ScreenshotSolverTileService,
                R.drawable.ic_qs_tile
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = "Tap to solve"
            }
            updateTile()
        }
    }

    companion object {
        const val PREFS_NAME = "nq_solver_prefs"
        const val KEY_PROJECTION_RESULT_CODE = "projection_result_code"
        const val KEY_PROJECTION_DATA = "projection_data"
        const val ACTION_REQUEST_PROJECTION = "com.example.n_queens_solver.REQUEST_PROJECTION"
        const val ACTION_REQUEST_OVERLAY = "com.example.n_queens_solver.REQUEST_OVERLAY"
    }
}
