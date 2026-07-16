package io.ente.mobile_ocr

import android.graphics.PointF
import kotlin.test.Test
import kotlin.test.assertEquals

class CharacterBoxGeometryTest {
    private fun point(x: Float, y: Float) = PointF().apply {
        this.x = x
        this.y = y
    }

    private val verticalBox = TextBox(
        listOf(
            point(10f, 10f),
            point(30f, 10f),
            point(30f, 110f),
            point(10f, 110f)
        )
    )
    private val spans = listOf(
        CharacterSpan("first", 1f, 0f, 0.5f),
        CharacterSpan("second", 1f, 0.5f, 1f)
    )

    @Test
    fun reversesVerticalSpansAfterTheFixedClockwiseCropRotation() {
        val characters = CharacterBoxGeometry.build(
            verticalBox,
            spans,
            rotated = false
        )

        assertEquals(60f, characters[0].points.minOf { it.y })
        assertEquals(10f, characters[1].points.minOf { it.y })
    }

    @Test
    fun keepsVerticalSpansAfterAnAdditionalClassifierRotation() {
        val characters = CharacterBoxGeometry.build(
            verticalBox,
            spans,
            rotated = true
        )

        assertEquals(10f, characters[0].points.minOf { it.y })
        assertEquals(60f, characters[1].points.minOf { it.y })
    }
}
