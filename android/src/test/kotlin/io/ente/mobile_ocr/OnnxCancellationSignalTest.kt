package io.ente.mobile_ocr

import kotlinx.coroutines.CancellationException
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class OnnxCancellationSignalTest {
    @Test
    fun rejectsWorkCancelledBeforeInferenceRegistration() {
        val signal = OnnxCancellationSignal()

        signal.cancel()

        assertTrue(signal.isCancelled)
        assertFailsWith<CancellationException> {
            signal.ensureActive()
        }
    }
}
