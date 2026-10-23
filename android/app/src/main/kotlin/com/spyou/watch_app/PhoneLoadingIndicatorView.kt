package com.spyou.watch_app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.content.ContextCompat
import androidx.graphics.shapes.CornerRounding
import androidx.graphics.shapes.Cubic
import androidx.graphics.shapes.circle
import androidx.graphics.shapes.Morph
import androidx.graphics.shapes.RoundedPolygon
import androidx.graphics.shapes.pill
import androidx.graphics.shapes.star

/**
 * Material 3 Expressive loading indicator: a shape continuously rotates while
 * morphing through the canonical rounded polygons, with a spring-driven 90°
 * kick on every shape change. Drawn as a plain View so the native player needs
 * no Compose dependency.
 */
class PhoneLoadingIndicatorView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    private data class Segment(
        val morph: Morph,
        val centerX: Float,
        val centerY: Float,
        val extent: Float,
    )

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = ContextCompat.getColor(context, R.color.phone_player_accent)
    }
    private val path = Path()
    private val shapes = buildShapes()
    private val segments = shapes.indices.map { i ->
        val from = shapes[i]
        val to = shapes[(i + 1) % shapes.size]
        val bounds = unionBounds(from, to)
        Segment(
            morph = Morph(from, to),
            centerX = (bounds[0] + bounds[2]) / 2f,
            centerY = (bounds[1] + bounds[3]) / 2f,
            extent = maxOf(bounds[2] - bounds[0], bounds[3] - bounds[1]),
        )
    }
    private val softer = OvershootInterpolator(0.9f)
    private var animator: ValueAnimator? = null
    private var startedAt = 0L
    private var staticShape = false

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (isShown) startMotion()
    }

    override fun onDetachedFromWindow() {
        stopMotion()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (isShown) startMotion() else stopMotion()
    }

    private fun startMotion() {
        if (animator != null) return
        staticShape = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !ValueAnimator.areAnimatorsEnabled()
        if (staticShape) {
            invalidate()
            return
        }
        startedAt = SystemClock.uptimeMillis()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = CYCLE_MS
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                invalidate()
            }
            start()
        }
    }

    private fun stopMotion() {
        animator?.cancel()
        animator = null
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val radius = minOf(width, height) / 2f
        if (radius <= 0f) return

        if (staticShape) {
            drawPolygon(canvas, RoundedPolygon.circle(), rotation = 0f, scale = radius * FILL)
            return
        }

        val elapsed = (SystemClock.uptimeMillis() - startedAt).toFloat()
        val step = elapsed / STEP_MS
        val segment = segments[(step.toInt()) % segments.size]
        val stepFraction = step - step.toInt()
        val morphT = softer.getInterpolation(minOf(stepFraction / MORPH_PORTION, 1f))

        setPath(segment.morph.asCubics(morphT))

        val scale = minOf(width, height) * FILL / segment.extent
        val rotation = elapsed / REVOLUTION_MS * 360f +
            step.toInt() * 90f +
            softer.getInterpolation(minOf(stepFraction / MORPH_PORTION, 1f)) * 90f

        canvas.save()
        canvas.translate(width / 2f, height / 2f)
        canvas.rotate(rotation)
        canvas.scale(scale, scale)
        canvas.translate(-segment.centerX, -segment.centerY)
        canvas.drawPath(path, paint)
        canvas.restore()
    }

    private fun setPath(cubics: List<Cubic>) {
        path.reset()
        var first = true
        for (cubic in cubics) {
            if (first) {
                path.moveTo(cubic.anchor0X, cubic.anchor0Y)
                first = false
            }
            path.cubicTo(
                cubic.control0X,
                cubic.control0Y,
                cubic.control1X,
                cubic.control1Y,
                cubic.anchor1X,
                cubic.anchor1Y,
            )
        }
        path.close()
    }

    private fun drawPolygon(canvas: Canvas, polygon: RoundedPolygon, rotation: Float, scale: Float) {
        setPath(polygon.cubics)
        canvas.save()
        canvas.translate(width / 2f, height / 2f)
        canvas.rotate(rotation)
        canvas.scale(scale, scale)
        canvas.drawPath(path, paint)
        canvas.restore()
    }

    private fun unionBounds(a: RoundedPolygon, b: RoundedPolygon): FloatArray {
        val first = a.calculateBounds()
        val second = b.calculateBounds()
        return floatArrayOf(
            minOf(first[0], second[0]),
            minOf(first[1], second[1]),
            maxOf(first[2], second[2]),
            maxOf(first[3], second[3]),
        )
    }

    private companion object {
        const val STEP_MS = 650f
        const val MORPH_PORTION = 0.62f
        const val CYCLE_MS = 650L * 7
        const val REVOLUTION_MS = STEP_MS * 7.178f
        const val FILL = 0.82f

        fun buildShapes(): List<RoundedPolygon> = listOf(
            RoundedPolygon.star(12, 1f, 0.78f, CornerRounding(0.35f, 0.8f), CornerRounding(0.35f, 0.8f)),
            RoundedPolygon.star(9, 1f, 0.9f, CornerRounding(0.5f, 1f), CornerRounding(0.5f, 1f)),
            RoundedPolygon(numVertices = 5, radius = 1f, rounding = CornerRounding(0.18f, 1f)),
            RoundedPolygon.pill(2f, 1.1f, 0.55f),
            RoundedPolygon.star(8, 1f, 0.72f, CornerRounding(0.3f, 1f), CornerRounding(0.2f, 1f)),
            RoundedPolygon.pill(2.2f, 1.15f, 0.575f),
            RoundedPolygon.star(4, 1f, 0.86f, CornerRounding(0.45f, 1f), CornerRounding(0.45f, 1f)),
        )
    }
}
