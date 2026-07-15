package io.ente.mobile_ocr

import android.graphics.Bitmap
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession

class TextRegionDetector(modelFiles: DetectionModelFiles) {
    companion object {
        private const val MINIMUM_DETECTION_CONFIDENCE = 0.5f
        private const val MAX_REGIONS = 1000
    }

    private val ortEnv = OrtEnvironment.getEnvironment()
    private val sessionOptions = OrtSession.SessionOptions().apply {
        setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
    }
    private val detectionSession = ortEnv.createSession(
        modelFiles.detectionModel.absolutePath,
        sessionOptions
    )

    fun detect(bitmap: Bitmap): List<DetectionCandidate> {
        return TextDetector(detectionSession, ortEnv)
            .collectHighConfidenceDetections(
                bitmap = bitmap,
                minimumDetectionConfidence = MINIMUM_DETECTION_CONFIDENCE,
                maxCandidates = MAX_REGIONS
            )
            .candidates
    }

    fun close() {
        detectionSession.close()
        sessionOptions.close()
    }
}
