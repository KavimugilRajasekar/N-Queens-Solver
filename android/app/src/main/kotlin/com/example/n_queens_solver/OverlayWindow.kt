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
        // Leave room for the header chip above the board
        val headerH     = (52 * density).toInt()
        val padding     = (14 * density).toInt()
        val totalH      = cardSize + headerH + (8 * density).toInt()

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
                        // Check close button hit area: top-right 52×52dp
                        val closeZone = 52 * density
                        if (ev.x >= cardSize - closeZone && ev.y <= closeZone) {
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
        } catch (_: Exception) {
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
    private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_PAPER; strokeWidth = 1f * 1f   // 1px
    }
    private val marginPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(38, 255, 0, 0); strokeWidth = 1.5f
    }
    private val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_WHITE
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = OverlayWindow.COLOR_NAVY
        style = Paint.Style.STROKE
        strokeWidth = 3f * 1f
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
    private val headerBgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
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
        val cw = cardW.toFloat()

        // ── 1. Notebook paper background ─────────────────────────────────────
        bgPaint.color = OverlayWindow.COLOR_BG
        canvas.drawRect(0f, 0f, cw, totalH.toFloat(), bgPaint)

        var ly = 0f
        while (ly < totalH) {
            canvas.drawLine(0f, ly, cw, ly, linePaint)
            ly += 30f
        }
        canvas.drawLine(60f, 0f, 60f, totalH.toFloat(), marginPaint)

        // ── 2. Hard drop shadow on card (offset 8,8) ─────────────────────────
        val cardTop   = headerH.toFloat() + 6 * dp
        val cardR     = 20 * dp
        val shadowR   = RectF(8 * dp, cardTop + 8 * dp, cw + 8 * dp, cardTop + cw + 8 * dp)
        canvas.drawRoundRect(shadowR, cardR, cardR, shadowPaint)

        // ── 3. White card ─────────────────────────────────────────────────────
        val cardR2 = RectF(0f, cardTop, cw, cardTop + cw)
        canvas.drawRoundRect(cardR2, cardR, cardR, cardPaint)
        borderPaint.strokeWidth = 3 * dp
        canvas.drawRoundRect(cardR2, cardR, cardR, borderPaint)

        // ── 4. Header chip ("SOLVED ✓" or "NO SOLUTION") ─────────────────────
        drawHeaderChip(canvas, cw, dp)

        // ── 5. Board grid OR failure explanation ──────────────────────────────
        val boardOff = padding.toFloat()
        val boardPx  = cw - boardOff * 2
        if (failReason != null) {
            drawFailPanel(canvas, boardOff, cardTop + boardOff, boardPx, failReason)
        } else {
            drawBoard(canvas, boardOff, cardTop + boardOff, boardPx)
        }

        // ── 6. Close button "×" ───────────────────────────────────────────────
        drawCloseButton(canvas, cw, dp)
    }

    // ── Header chip ───────────────────────────────────────────────────────────

    private fun drawHeaderChip(canvas: Canvas, cw: Float, dp: Float) {
        val chipW  = 170 * dp
        val chipH  = 40 * dp
        val chipX  = (cw - chipW) / 2
        val chipY  = 6 * dp
        val chipR  = 12 * dp

        val isFail = failReason != null
        val chipColor = if (isFail) Color.parseColor("#FF7043") else OverlayWindow.COLOR_GOLD
        val chipText  = if (isFail) "NO SOLUTION  ✗" else "SOLVED  ✓"

        // Shadow
        val shadowRect = RectF(chipX + 4 * dp, chipY + 4 * dp, chipX + chipW + 4 * dp, chipY + chipH + 4 * dp)
        canvas.drawRoundRect(shadowRect, chipR, chipR, shadowPaint)

        // Chip background
        headerBgPaint.color = chipColor
        val chipRect = RectF(chipX, chipY, chipX + chipW, chipY + chipH)
        canvas.drawRoundRect(chipRect, chipR, chipR, headerBgPaint)
        borderPaint.strokeWidth = 2 * dp
        canvas.drawRoundRect(chipRect, chipR, chipR, borderPaint)

        // Text
        headerTextPaint.color = if (isFail) Color.WHITE else OverlayWindow.COLOR_NAVY
        headerTextPaint.textSize = 14 * dp
        canvas.drawText(chipText, chipX + chipW / 2, chipY + chipH * 0.67f, headerTextPaint)
    }

    // ── Failure explanation panel ─────────────────────────────────────────────

    private fun drawFailPanel(canvas: Canvas, ox: Float, oy: Float, panelPx: Float, reason: String) {
        val panelH = panelPx   // square, same as board area
        val r      = 12 * dp

        // Pale red background panel
        val panelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FFF3F0") }
        val panelRect  = RectF(ox, oy, ox + panelPx, oy + panelH)
        canvas.drawRoundRect(panelRect, r, r, panelPaint)

        // Red dashed border
        val borderP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FF7043")
            style = Paint.Style.STROKE
            strokeWidth = 2.5f * dp
            pathEffect = android.graphics.DashPathEffect(floatArrayOf(12f * dp, 6f * dp), 0f)
        }
        canvas.drawRoundRect(panelRect, r, r, borderP)

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

        // Board outer border (2dp navyBlue)
        borderPaint.strokeWidth = 2 * dp
        borderPaint.style = Paint.Style.STROKE
        val boardRect = RectF(ox, oy, ox + boardPx, oy + boardPx)
        canvas.drawRoundRect(boardRect, 8 * dp, 8 * dp, cellFillPaint.apply { color = Color.WHITE; style = Paint.Style.FILL })
        canvas.drawRoundRect(boardRect, 8 * dp, 8 * dp, borderPaint)

        // Clip board
        canvas.save()
        val clipPath = Path().apply { addRoundRect(boardRect, 8 * dp, 8 * dp, Path.Direction.CW) }
        canvas.clipPath(clipPath)

        // Draw cells
        for (r in 0 until size) {
            for (c in 0 until size) {
                val l = ox + c * cell
                val t = oy + r * cell
                val rect = RectF(l, t, l + cell, t + cell)

                // Region fill
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

        // Queen markers ★
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

    private fun drawCloseButton(canvas: Canvas, cw: Float, dp: Float) {
        val btnSize = 36 * dp
        val margin  = 8 * dp
        val bx = cw - btnSize - margin
        val by = margin

        // Circle bg (white + navy border)
        val circPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        canvas.drawCircle(bx + btnSize / 2, by + btnSize / 2, btnSize / 2, circPaint)
        val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = OverlayWindow.COLOR_NAVY; style = Paint.Style.STROKE; strokeWidth = 2 * dp
        }
        canvas.drawCircle(bx + btnSize / 2, by + btnSize / 2, btnSize / 2, strokeP)

        // × character
        closePaint.textSize = 20 * dp
        canvas.drawText("×", bx + btnSize / 2, by + btnSize * 0.70f, closePaint)
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
