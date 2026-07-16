package io.ente.mobile_ocr

import ai.onnxruntime.OnnxTensorLike
import ai.onnxruntime.OrtException
import ai.onnxruntime.OrtSession
import kotlinx.coroutines.CancellationException

class OnnxCancellationSignal {
    private val lock = Any()
    private val activeRuns = mutableSetOf<OrtSession.RunOptions>()

    @Volatile
    private var cancelled = false

    val isCancelled: Boolean
        get() = cancelled

    fun cancel() {
        synchronized(lock) {
            if (cancelled) {
                return
            }
            cancelled = true
            activeRuns.forEach { options ->
                runCatching { options.setTerminate(true) }
            }
        }
    }

    fun ensureActive() {
        if (cancelled) {
            throw CancellationException("OCR request was cancelled")
        }
    }

    fun run(
        session: OrtSession,
        inputs: Map<String, OnnxTensorLike>
    ): OrtSession.Result {
        ensureActive()
        val options = OrtSession.RunOptions()
        synchronized(lock) {
            if (cancelled) {
                options.close()
                throw CancellationException("OCR request was cancelled")
            }
            activeRuns.add(options)
        }

        try {
            val result = session.run(inputs, options)
            if (cancelled) {
                result.close()
                throw CancellationException("OCR request was cancelled")
            }
            return result
        } catch (error: OrtException) {
            if (cancelled) {
                throw CancellationException("OCR request was cancelled").also {
                    it.initCause(error)
                }
            }
            throw error
        } finally {
            synchronized(lock) {
                activeRuns.remove(options)
                options.close()
            }
        }
    }
}

internal fun runOnnx(
    session: OrtSession,
    inputs: Map<String, OnnxTensorLike>,
    cancellationSignal: OnnxCancellationSignal?
): OrtSession.Result {
    return cancellationSignal?.run(session, inputs) ?: session.run(inputs)
}
