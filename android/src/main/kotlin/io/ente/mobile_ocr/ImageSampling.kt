package io.ente.mobile_ocr

object ImageSampling {
    fun calculateInSampleSize(
        width: Int,
        height: Int,
        maxDimension: Int,
        maxPixels: Long
    ): Int {
        if (width <= 0 || height <= 0) {
            return 1
        }

        var sampleSize = 1
        while (true) {
            val sampledWidth = width / sampleSize
            val sampledHeight = height / sampleSize
            val sampledPixels = sampledWidth.toLong() * sampledHeight
            if (
                sampledWidth <= maxDimension &&
                sampledHeight <= maxDimension &&
                sampledPixels <= maxPixels
            ) {
                return sampleSize
            }
            sampleSize *= 2
        }
    }
}
