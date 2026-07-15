package io.ente.mobile_ocr

import kotlin.test.Test
import kotlin.test.assertEquals

class ImageSamplingTest {
    @Test
    fun keepsImagesWithinBoundsUnchanged() {
        assertEquals(
            1,
            ImageSampling.calculateInSampleSize(1920, 1080, 4096, 12_000_000)
        )
    }

    @Test
    fun samplesUntilDimensionAndPixelLimitsAreMet() {
        assertEquals(
            4,
            ImageSampling.calculateInSampleSize(12000, 9000, 4096, 12_000_000)
        )
    }

    @Test
    fun usesPowerOfTwoSampleSizes() {
        assertEquals(
            8,
            ImageSampling.calculateInSampleSize(16000, 12000, 2048, 4_000_000)
        )
    }
}
