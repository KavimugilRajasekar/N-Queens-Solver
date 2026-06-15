package com.example.n_queens_solver

import android.content.Context
import android.graphics.*
import android.os.Build
import android.view.*
import android.view.animation.OvershootInterpolator

/**
 * Funky draggable overlay that matches the in-app N-Queens board style exactly:
 *
 * Visual language:
 *   • Notebook-paper background (light-blue horizontal rules + red margin line)
 *   • Pastel region fills — same 12-color palette as RegionColors.dart
 *   • Hard drop-shadow (no blur) on the outer card — offset (8,8) navyBlue 20% alpha
 *   • Thick navyBlue border (3dp) on the card, 2dp on inner board
 *   • Queen marker: ★ starburst at 78% of cell size, navyBlue
 *   • Region-border emphasis: slightly darker shade on region boundaries
 *   • Subtle slight-rotation on the header title chip (-0.015 rad)
 *   • "SOLVED ✓" gold chip header + "×" close button (navyBlue, DynaPuff style)
 *   • Drag-to-move, pop-in entrance animation
 */
object OverlayWindow {

    var isVisible = false
        private set

    private var windowManager: WindowManager? = null
    private var rootView: View? = null

    // ── App color constants (matches AppColors.dart) ──────────────────────────
    internal val COLOR_NAVY    = Color.parseColor("#3F51B5")
    internal val COLOR_GOLD    = Color.parseColor("#FFD54F")
    internal val COLOR_WHITE   = Color.WHITE
    internal val COLOR_BG      = Color.parseColor("#FCFCFC")
    internal val COLOR_PAPER   = Color.parseColor("#E3F2FD")
    internal val COLOR_SHADOW  = Color.argb(51, 63, 81, 181)   // navyBlue 20%
    internal val COLOR_CELL_BORDER = Color.argb(13, 0, 0, 0)   // black 5%
    internal val COLOR_DARK    = Color.parseColor("#212121")    // near-black body text

    // ── Region palette (matches RegionColors.dart exactly) ────────────────────
    private val REGION_PALETTE = intArrayOf(
        Color.parseColor("#FFB3B3"), // 1 Red 200
        Color.parseColor("#B3D9FF"), // 2 Blue 200
        Color.parseColor("#B3FFB3"), // 3 Green 200
        Color.parseColor("#FFD9B3"), // 4 Orange 200
        Color.parseColor("#E6B3FF"), // 5 Purple 200
        Color.parseColor("#B3FFFF"), // 6 Cyan 200
        Color.parseColor("#FFB3E6"), // 7 Pink 200
        Color.parseColor("#B3B3FF"), // 8 Indigo 200
        Color.parseColor("#FFE6B3"), // 9 Amber 200
        Color.parseColor("#B3FFE6"), // 10 Teal 200
        Color.parseColor("#E6FFB3"), // 11 Lime 200
        Color.parseColor("#D9B38C")  // 12 Brown 200
    )

    fun regionColor(id: Int): Int {
        if (id <= 0) return Color.WHITE
        return REGION_PALETTE[(id - 1) % REGION_PALETTE.size]
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    fun show(
        context: Context,
        size: Int,
        regionIds: List<List<Int>>,
        solution: Map<Int, Pair<Int, Int>>?,
        failReason: String? = null
    ) {
        if (isVisible) return

        val appCtx = context.applicationContext
        val wm     = appCtx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val metrics     = appCtx.resources.displayMetrics
        val screenW     = metrics.widthPixels
        val screenH     = metrics.heightPixels
        val density     = metrics.density

        // Card is 88% of screen width, square-ish
        val cardSize    = (screenW * 0.88f).toInt()
        val headerH     = (64 * density).toInt() // Increased to 64dp for title + status
        val padding     = (14 * density).toInt()
        val shadowSize  = (8 * density).toInt()
        val boardPx     = cardSize - shadowSize - padding * 2
        val totalH      = headerH + boardPx + padding * 2 + shadowSize

        val root = OverlayRootView(appCtx, density, cardSize, totalH, headerH, padding,
                                   size, regionIds, solution, failReason)

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

        val params = WindowManager.LayoutParams(
            cardSize,
            totalH,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (screenW - cardSize) / 2
            y = screenH / 7
        }

        // Touch: close button tap OR drag-to-move
        var ix = 0; var iy = 0; var tx = 0f; var ty = 0f; var dragged = false
        root.setOnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    ix = params.x; iy = params.y
                    tx = ev.rawX;  ty = ev.rawY
                    dragged = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - tx; val dy = ev.rawY - ty
                    if (!dragged && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) dragged = true
                    params.x = ix + dx.toInt(); params.y = iy + dy.toInt()
                    try { wm.updateViewLayout(root, params) } catch (_: Exception) {}
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!dragged) {
                        // Check close button hit area: top-right 44×44dp on the card (excluding shadow)
                        val cW = cardSize - shadowSize
                        val hitCloseX = ev.x >= cW - 44 * density
                        val hitCloseY = ev.y <= 44 * density
                        if (hitCloseX && hitCloseY) {
                            dismiss()
                        }
                    }
                    true
                }
                else -> false
            }
        }

        try {
            wm.addView(root, params)
            rootView  = root
            isVisible = true

            // Pop-in entrance animation
            root.scaleX = 0.4f; root.scaleY = 0.4f; root.alpha = 0f
            root.animate()
                .scaleX(1f).scaleY(1f).alpha(1f)
                .setDuration(320)
                .setInterpolator(OvershootInterpolator(1.6f))
                .start()
        } catch (e: Exception) {
            android.util.Log.e("OverlayWindow", "Failed to show overlay window: ${e.message}", e)
            isVisible = false
        }
    }

    fun dismiss() {
        val v  = rootView  ?: return
        val wm = windowManager ?: return
        v.animate()
            .scaleX(0.3f).scaleY(0.3f).alpha(0f)
            .setDuration(200)
            .withEndAction {
                try { wm.removeView(v) } catch (_: Exception) {}
                rootView      = null
                windowManager = null
                isVisible     = false
            }.start()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// The single compound view that draws everything with Canvas
// ─────────────────────────────────────────────────────────────────────────────

private class OverlayRootView(
    context: Context,
    private val dp: Float,
    private val cardW: Int,
    private val totalH: Int,
    private val headerH: Int,
    private val padding: Int,
    private val size: Int,
    private val regionIds: List<List<Int>>,
    private val solution: Map<Int, Pair<Int, Int>>?,
    private val failReason: String?
) : View(context) {

    // Pre-compute queen cells (0-based row,col)
    private val queenCells: Set<Long> = solution?.values
        ?.map { packRC(it.first - 1, it.second - 1) }?.toSet() ?: emptySet()

    // Paints
    private val bgPaint   = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_WHITE
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_NAVY
        style = Paint.Style.STROKE
        strokeWidth = 3f * dp
    }
    private val cellBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_CELL_BORDER
        style = Paint.Style.STROKE
        strokeWidth = 0.75f
    }
    private val regionBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(55, 63, 81, 181)   // navyBlue 22%
        style = Paint.Style.STROKE
        strokeWidth = 2.2f
    }
    private val cellFillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val queenPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_NAVY
        textAlign = Paint.Align.CENTER
    }
    private val headerTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_NAVY
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val closePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_NAVY
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_SHADOW
    }

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)   // needed for shadow drawing
    }

    override fun onMeasure(w: Int, h: Int) = setMeasuredDimension(cardW, totalH)

    override fun onDraw(canvas: Canvas) {
        // Shadow is offset by 8dp to bottom-right
        val shadowOffset = 8 * dp
        val cW = cardW.toFloat() - shadowOffset
        val cH = totalH.toFloat() - shadowOffset

        // Card rectangle (sharp corners)
        val cardRect = RectF(0f, 0f, cW, cH)
        // Shadow rectangle (sharp corners)
        val shadowRect = RectF(shadowOffset, shadowOffset, cardW.toFloat(), totalH.toFloat())

        // ── 1. Draw Card Drop Shadow ─────────────────────────────────────────
        canvas.drawRect(shadowRect, shadowPaint)

        // ── 2. Draw Card Background ──────────────────────────────────────────
        canvas.drawRect(cardRect, cardPaint)

        // ── 3. Draw Card Border ──────────────────────────────────────────────
        borderPaint.strokeWidth = 3 * dp
        canvas.drawRect(cardRect, borderPaint)

        // ── 4. Draw Header separator line ────────────────────────────────────
        borderPaint.strokeWidth = 1.5f * dp
        canvas.drawLine(0f, headerH.toFloat(), cW, headerH.toFloat(), borderPaint)

        // ── 5. Draw Header Title & Subtitle ──────────────────────────────────
        val titleText = "N-Queens Studio"
        headerTextPaint.textSize = 16 * dp
        headerTextPaint.color = OverlayWindow.COLOR_NAVY
        canvas.drawText(titleText, cW / 2, headerH * 0.46f, headerTextPaint)

        val isFail = failReason != null
        val subText = if (isFail) "Unsolvable  ✗" else "Solvable  ✓"
        val subColor = if (isFail) Color.parseColor("#E53935") else Color.parseColor("#4CAF50")
        val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = subColor
            textAlign = Paint.Align.CENTER
            textSize = 12 * dp
            isFakeBoldText = true
        }
        canvas.drawText(subText, cW / 2, headerH * 0.82f, subPaint)

        // ── 6. Board grid OR failure explanation ──────────────────────────────
        val boardOff = padding.toFloat()
        val boardPx  = cW - boardOff * 2
        val boardTop = headerH.toFloat() + boardOff

        if (failReason != null) {
            drawFailPanel(canvas, boardOff, boardTop, boardPx, failReason)
        } else {
            drawBoard(canvas, boardOff, boardTop, boardPx)
        }

        // ── 7. Close button "×" (sharp cornered square) ──────────────────────
        drawCloseButton(canvas, cW, dp)
    }

    // ── Failure explanation panel ─────────────────────────────────────────────

    private fun drawFailPanel(canvas: Canvas, ox: Float, oy: Float, panelPx: Float, reason: String) {
        val panelH = panelPx   // square, same as board area

        // Pale red background panel (sharp)
        val panelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FFF3F0") }
        val panelRect  = RectF(ox, oy, ox + panelPx, oy + panelH)
        canvas.drawRect(panelRect, panelPaint)

        // Red dashed border (sharp)
        val borderP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FF7043")
            style = Paint.Style.STROKE
            strokeWidth = 2.5f * dp
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(12f * dp, 6f * dp), 0f)
        }
        canvas.drawRect(panelRect, borderP)

        // Big ✗ icon
        val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FF7043")
            textAlign = Paint.Align.CENTER
            textSize = 38 * dp
            isFakeBoldText = true
        }
        canvas.drawText("✗", ox + panelPx / 2, oy + panelH * 0.28f, iconPaint)

        // "Unsolvable board" title
        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#BF360C")
            textAlign = Paint.Align.CENTER
            textSize = 14 * dp
            isFakeBoldText = true
        }
        canvas.drawText("Unsolvable Board", ox + panelPx / 2, oy + panelH * 0.44f, titlePaint)

        // Reason text — word-wrap manually
        val bodyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayWindow.COLOR_DARK
            textAlign = Paint.Align.CENTER
            textSize = 11 * dp
        }
        val maxWidth  = panelPx - 32 * dp
        val lineH     = 16 * dp
        var lineY     = oy + panelH * 0.55f
        val words     = reason.split(" ")
        var line      = ""
        for (word in words) {
            val test = if (line.isEmpty()) word else "$line $word"
            if (bodyPaint.measureText(test) <= maxWidth) {
                line = test
            } else {
                if (line.isNotEmpty()) canvas.drawText(line, ox + panelPx / 2, lineY, bodyPaint)
                lineY += lineH
                line   = word
            }
        }
        if (line.isNotEmpty()) canvas.drawText(line, ox + panelPx / 2, lineY, bodyPaint)

        // Bottom hint
        val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayWindow.COLOR_NAVY
            textAlign = Paint.Align.CENTER
            textSize = 10 * dp
        }
        canvas.drawText("Try re-scanning with a clearer photo", ox + panelPx / 2, oy + panelH * 0.92f, hintPaint)
    }

    // ── Board grid ────────────────────────────────────────────────────────────

    private fun drawBoard(canvas: Canvas, ox: Float, oy: Float, boardPx: Float) {
        val cell = boardPx / size

        // Board outer border (2dp navyBlue, sharp cornered)
        borderPaint.strokeWidth = 2 * dp
        borderPaint.style = Paint.Style.STROKE
        val boardRect = RectF(ox, oy, ox + boardPx, oy + boardPx)
        canvas.drawRect(boardRect, cellFillPaint.apply { color = Color.WHITE; style = Paint.Style.FILL })
        canvas.drawRect(boardRect, borderPaint)

        // Clip board (sharp cornered)
        canvas.save()
        canvas.clipRect(boardRect)

        // Draw cells
        for (r in 0 until size) {
            for (c in 0 until size) {
                val l = ox + c * cell
                val t = oy + r * cell
                val rect = RectF(l, t, l + cell, t + cell)

                // Region fill (funky board colors inside!)
                val id = safeId(r, c)
                cellFillPaint.color = OverlayWindow.regionColor(id)
                cellFillPaint.style = Paint.Style.FILL
                canvas.drawRect(rect, cellFillPaint)

                // Subtle cell border
                canvas.drawRect(rect, cellBorderPaint)
            }
        }

        // Region boundaries (draw thicker line where adjacent cells differ)
        for (r in 0 until size) {
            for (c in 0 until size) {
                val l = ox + c * cell
                val t = oy + r * cell
                val id = safeId(r, c)

                // Right neighbor
                if (c + 1 < size && safeId(r, c + 1) != id) {
                    canvas.drawLine(l + cell, t, l + cell, t + cell, regionBorderPaint)
                }
                // Bottom neighbor
                if (r + 1 < size && safeId(r + 1, c) != id) {
                    canvas.drawLine(l, t + cell, l + cell, t + cell, regionBorderPaint)
                }
            }
        }

        // Queen markers ★ (funky!)
        queenPaint.textSize = cell * 0.75f
        for (r in 0 until size) {
            for (c in 0 until size) {
                if (packRC(r, c) in queenCells) {
                    val l = ox + c * cell
                    val t = oy + r * cell
                    val cx = l + cell / 2
                    val cy = t + cell * 0.745f
                    canvas.drawText("★", cx, cy, queenPaint)
                }
            }
        }

        canvas.restore()
    }

    // ── Close button ──────────────────────────────────────────────────────────

    private fun drawCloseButton(canvas: Canvas, cW: Float, dp: Float) {
        val btnSize = 26 * dp
        val offset  = 8 * dp
        val bx = cW - btnSize - offset
        val by = offset

        // Square bg (white + navy border)
        val rect = RectF(bx, by, bx + btnSize, by + btnSize)
        val bgP = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        canvas.drawRect(rect, bgP)

        val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayWindow.COLOR_NAVY
            style = Paint.Style.STROKE
            strokeWidth = 2 * dp
        }
        canvas.drawRect(rect, strokeP)

        // × character
        closePaint.textSize = 18 * dp
        canvas.drawText("×", bx + btnSize / 2, by + btnSize * 0.73f, closePaint)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun safeId(r: Int, c: Int): Int {
        if (r < 0 || r >= regionIds.size) return 0
        val row = regionIds[r]
        if (c < 0 || c >= row.size) return 0
        return row[c]
    }

    private fun packRC(r: Int, c: Int): Long = r.toLong() shl 32 or c.toLong()
}
