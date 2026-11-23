package dev.sagron.zerotrustbrowser

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.widget.FrameLayout

/**
 * A tab's WebView that notices when the page itself tries to scroll above
 * its top (B28). Chromium reports scrolling the page can't take through
 * onOverScrolled; a box inside the page that still scrolls takes the
 * finger first, so pulling inside a scrolled list never reloads.
 */
class PageWebView(context: Context) : WebView(context) {
    /** Set when, during this touch, the page was pulled past its top. */
    var pulledPastTop = false

    override fun onOverScrolled(scrollX: Int, scrollY: Int, clampedX: Boolean, clampedY: Boolean) {
        super.onOverScrolled(scrollX, scrollY, clampedX, clampedY)
        if (clampedY && scrollY <= 0) pulledPastTop = true
    }
}

/**
 * B28: pull down at the top of a page to reload it. Every touch still goes
 * to the page; this only watches, and shows a small circle that fills as
 * the finger pulls. Letting go past [trigger] reloads.
 */
class PullToRefreshLayout(
    context: Context,
    private val page: PageWebView,
    private val onRefresh: () -> Unit,
) : FrameLayout(context) {
    private val density = resources.displayMetrics.density
    private val trigger = 88 * density
    private val maxPull = 128 * density
    private val indicator = Indicator(context)

    private var atTop = false
    private var pullFrom = Float.NaN
    private var pull = 0f
    /** The finger is pulling now; the shown [pull] can lag while it hides. */
    private var pulling = false
    private var hiding: ValueAnimator? = null

    init {
        addView(page, LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        val size = (40 * density).toInt()
        addView(indicator, LayoutParams(size, size).apply { gravity = android.view.Gravity.CENTER_HORIZONTAL })
        indicator.visibility = View.INVISIBLE
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ZtTab.pullToRefresh) watch(ev)
        return super.dispatchTouchEvent(ev)
    }

    private fun watch(ev: MotionEvent) {
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                hiding?.cancel()
                atTop = !page.canScrollVertically(-1)
                page.pulledPastTop = false
                pullFrom = Float.NaN
                setPull(0f)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                // Pinch zoom: no reload for the rest of this touch.
                reset()
                atTop = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (!atTop || !page.pulledPastTop) return
                if (pullFrom.isNaN()) pullFrom = ev.y
                val moved = ev.y - pullFrom
                if (moved < -8 * density) {
                    // Back up: the page scrolls again, no reload.
                    reset()
                    atTop = false
                    return
                }
                pulling = true
                setPull((moved * 0.6f).coerceIn(0f, maxPull))
            }
            MotionEvent.ACTION_UP -> {
                val reload = pulling && pull >= trigger
                reset()
                if (reload) onRefresh()
            }
            MotionEvent.ACTION_CANCEL -> reset()
        }
    }

    private fun reset() {
        pulling = false
        page.pulledPastTop = false
        pullFrom = Float.NaN
        if (pull <= 0f) {
            setPull(0f)
            return
        }
        hiding?.cancel()
        hiding = ValueAnimator.ofFloat(pull, 0f).apply {
            duration = 160
            addUpdateListener { setPull(it.animatedValue as Float) }
            start()
        }
    }

    private fun setPull(value: Float) {
        pull = value
        if (value <= 0f) {
            indicator.visibility = View.INVISIBLE
            return
        }
        indicator.visibility = View.VISIBLE
        indicator.translationY = value - 44 * density
        indicator.progress = (value / trigger).coerceAtMost(1f)
        indicator.invalidate()
    }

    /** The circle under the finger: an arc that closes at [trigger]. */
    private class Indicator(context: Context) : View(context) {
        var progress = 0f
        private val density = resources.displayMetrics.density
        private val disc = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 3 * density
            strokeCap = Paint.Cap.ROUND
        }
        private val box = RectF()

        init {
            elevation = 4 * density
        }

        override fun onDraw(canvas: Canvas) {
            val r = width / 2f
            canvas.drawCircle(r, r, r, disc)
            // The browser's orange once letting go reloads; grey before.
            ring.color = if (progress >= 1f) Color.rgb(0xF9, 0x73, 0x16) else Color.GRAY
            val inset = 11 * density
            box.set(inset, inset, width - inset, height - inset)
            canvas.drawArc(box, -90f, 360f * progress, false, ring)
        }
    }
}
