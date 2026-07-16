package io.ente.mobile_ocr

import android.graphics.PointF
import kotlin.math.hypot

object CharacterBoxGeometry {
    fun build(
        textBox: TextBox,
        spans: List<CharacterSpan>,
        rotated: Boolean
    ): List<CharacterBox> {
        if (spans.isEmpty()) {
            return emptyList()
        }

        val ordered = ImageUtils.orderPointsClockwise(textBox.points)
        if (ordered.size != 4) {
            return emptyList()
        }

        val topLeft = ordered[0]
        val topRight = ordered[1]
        val bottomRight = ordered[2]
        val bottomLeft = ordered[3]
        val horizontalLength = maxOf(
            distance(topLeft, topRight),
            distance(bottomLeft, bottomRight)
        )
        val verticalLength = maxOf(
            distance(topLeft, bottomLeft),
            distance(topRight, bottomRight)
        )
        val isVertical = verticalLength > horizontalLength * 1.5f
        val epsilon = 1e-4f

        return spans.mapNotNull { span ->
            var start = span.startRatio
            var end = span.endRatio
            if (rotated != isVertical) {
                val reversedStart = 1f - end
                val reversedEnd = 1f - start
                start = reversedStart.coerceIn(0f, 1f)
                end = reversedEnd.coerceIn(start + epsilon, 1f)
            }

            val clampedStart = start.coerceIn(0f, 1f)
            val clampedEnd = end.coerceIn(clampedStart + epsilon, 1f)
            if (clampedEnd - clampedStart <= epsilon) {
                return@mapNotNull null
            }

            val points = if (isVertical) {
                val leftStart = interpolate(topLeft, bottomLeft, clampedStart)
                val leftEnd = interpolate(topLeft, bottomLeft, clampedEnd)
                val rightStart = interpolate(topRight, bottomRight, clampedStart)
                val rightEnd = interpolate(topRight, bottomRight, clampedEnd)
                listOf(leftStart, rightStart, rightEnd, leftEnd)
            } else {
                val topStart = interpolate(topLeft, topRight, clampedStart)
                val topEnd = interpolate(topLeft, topRight, clampedEnd)
                val bottomStart = interpolate(bottomLeft, bottomRight, clampedStart)
                val bottomEnd = interpolate(bottomLeft, bottomRight, clampedEnd)
                listOf(topStart, topEnd, bottomEnd, bottomStart)
            }

            CharacterBox(
                text = span.text,
                confidence = span.confidence,
                points = points
            )
        }
    }

    private fun interpolate(start: PointF, end: PointF, ratio: Float): PointF {
        val clamped = ratio.coerceIn(0f, 1f)
        return PointF().apply {
            x = start.x + (end.x - start.x) * clamped
            y = start.y + (end.y - start.y) * clamped
        }
    }

    private fun distance(first: PointF, second: PointF): Float {
        return hypot(second.x - first.x, second.y - first.y)
    }
}
