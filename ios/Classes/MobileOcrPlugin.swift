import Flutter
import Foundation
import UIKit
import Vision

public class MobileOcrPlugin: NSObject, FlutterPlugin {
    private let requestLock = NSLock()
    private var activeRequests: [String: VNRequest] = [:]
    private var cancelledRequestIds: Set<String> = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "mobile_ocr", binaryMessenger: registrar.messenger())
        let instance = MobileOcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
        case "prepareModels":
            // iOS uses built-in Vision framework, no model download needed
            result([
                "isReady": true,
                "version": "iOS-Vision",
                "modelPath": "system"
            ])
        case "getModelAvailability":
            result([
                "detectorReady": true,
                "recognizerReady": true,
                "version": "iOS-Vision"
            ])
        case "detectText":
            handleTextDetection(call: call, result: result)
        case "detectTextRegions":
            handleTextRegionDetection(call: call, result: result)
        case "cancelRequest":
            handleCancelRequest(call: call, result: result)
        case "hasText":
            handleQuickTextCheck(call: call, result: result)
        case "ensureImageIsDisplayable":
            guard let arguments = call.arguments as? [String: Any],
                  let imagePath = arguments["imagePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "Image path is required",
                                    details: nil))
                return
            }
            result(imagePath)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleTextDetection(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let imagePath = arguments["imagePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT",
                               message: "Image path is required",
                               details: nil))
            return
        }

        let includeAllConfidenceScores = (arguments["includeAllConfidenceScores"] as? Bool) ?? false
        let requestId = arguments["requestId"] as? String
        // Lower confidence thresholds to be more inclusive
        let minConfidence: Float = includeAllConfidenceScores ? 0.0 : 0.3

        detectTextInImage(imagePath: imagePath,
                         minConfidence: minConfidence,
                         requestId: requestId,
                         result: result)
    }

    private func handleTextRegionDetection(call: FlutterMethodCall,
                                           result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let imagePath = arguments["imagePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT",
                               message: "Image path is required",
                               details: nil))
            return
        }
        let requestId = arguments["requestId"] as? String

        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_NOT_FOUND",
                                       message: "Image file does not exist",
                                       details: nil))
                }
                return
            }
            guard let image = UIImage(contentsOfFile: imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to load image from path",
                                       details: nil))
                }
                return
            }

            var fixedImage = image
            if image.imageOrientation != .up {
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = image.scale
                format.opaque = false
                fixedImage = UIGraphicsImageRenderer(
                    size: image.size,
                    format: format
                ).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
            }

            guard let cgImage = fixedImage.cgImage else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to get CGImage",
                                       details: nil))
                }
                return
            }

            var regions: [[String: Any]] = []
            var callbackError: Error?
            let request = VNDetectTextRectanglesRequest { request, error in
                if let error = error {
                    callbackError = error
                    return
                }
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let observations = request.results as? [VNTextObservation] ?? []
                regions = observations.map { observation in
                    let points: [[String: Double]] = [
                        ["x": Double(observation.topLeft.x * width),
                         "y": Double((1 - observation.topLeft.y) * height)],
                        ["x": Double(observation.topRight.x * width),
                         "y": Double((1 - observation.topRight.y) * height)],
                        ["x": Double(observation.bottomRight.x * width),
                         "y": Double((1 - observation.bottomRight.y) * height)],
                        ["x": Double(observation.bottomLeft.x * width),
                         "y": Double((1 - observation.bottomLeft.y) * height)]
                    ]
                    return [
                        "confidence": Double(observation.confidence),
                        "points": points
                    ]
                }
            }
            request.reportCharacterBoxes = false
            self.register(request, requestId: requestId)

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:])
                    .perform([request])
            } catch {
                callbackError = error
            }
            let requestWasCancelled = self.finishRequest(
                request,
                requestId: requestId
            )

            DispatchQueue.main.async {
                if requestWasCancelled {
                    result(FlutterError(code: "CANCELLED",
                                       message: "OCR request was cancelled",
                                       details: nil))
                } else if let error = callbackError {
                    result(FlutterError(code: "DETECTION_ERROR",
                                       message: "Failed to detect text regions",
                                       details: error.localizedDescription))
                } else {
                    result([
                        "regions": regions,
                        "imageWidth": cgImage.width,
                        "imageHeight": cgImage.height
                    ])
                }
            }
        }
    }

    private func handleQuickTextCheck(call: FlutterMethodCall,
                                      result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let imagePath = arguments["imagePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT",
                               message: "Image path is required",
                               details: nil))
            return
        }

        // Use same threshold as detectText for consistency
        // Text validation will filter out false positives
        quickDetectText(imagePath: imagePath,
                        minConfidence: 0.3,
                        result: result)
    }

    private func detectTextInImage(imagePath: String,
                                  minConfidence: Float,
                                  requestId: String?,
                                  result: @escaping FlutterResult) {
        // Move processing to background queue
        let workItem = DispatchWorkItem {
            let fileName = URL(fileURLWithPath: imagePath).lastPathComponent
            guard FileManager.default.fileExists(atPath: imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_NOT_FOUND",
                                       message: "Image file does not exist",
                                       details: nil))
                }
                return
            }
            guard let image = UIImage(contentsOfFile: imagePath) else {
                MobileOcrPlugin.logDebug("detectText load failure for \(fileName)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to load image from path",
                                       details: nil))
                }
                return
            }

            // Fix image orientation using modern API
            var fixedImage = image
            var orientationFixed = false
            if image.imageOrientation != .up {
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = image.scale  // preserve original pixel density
                format.opaque = false
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                fixedImage = renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                orientationFixed = true
            }

            guard let cgImage = fixedImage.cgImage else {
                MobileOcrPlugin.logDebug("detectText CGImage missing for \(fileName)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to get CGImage",
                                       details: nil))
                }
                return
            }

            let colorSpaceName = cgImage.colorSpace?.name as String? ?? "unknown"
            let originalSize = "\(Int(image.size.width))x\(Int(image.size.height))"
            let renderedSize = "\(cgImage.width)x\(cgImage.height)"
            MobileOcrPlugin.logDebug(
                "detectText start file=\(fileName) minConf=\(String(format: "%.2f", minConfidence))"
                + " originalOrient=\(image.imageOrientation.rawValue)"
                + " orientationFixed=\(orientationFixed)"
                + " size=\(originalSize) renderedSize=\(renderedSize)"
                + " colorSpace=\(colorSpaceName) bpc=\(cgImage.bitsPerComponent)"
            )

            // Create Vision request
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var detectedTexts: [[String: Any]] = []
            var observationCount = 0
            var discardedLowConfidence = 0
            var previewSamples: [String] = []
            var callbackError: Error?

            let request = VNRecognizeTextRequest { (request, error) in
                if let error = error {
                    callbackError = error
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                observationCount = observations.count

                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }

                    // Filter by confidence
                    if topCandidate.confidence < minConfidence {
                        discardedLowConfidence += 1
                        continue
                    }

                    if previewSamples.count < 5 {
                        let sanitized = topCandidate.string
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        previewSamples.append(
                            "\(String(format: "%.2f", topCandidate.confidence))|\(sanitized)"
                        )
                    }

                    // Convert normalized coordinates to image coordinates
                    let imageWidth = CGFloat(cgImage.width)
                    let imageHeight = CGFloat(cgImage.height)

                    // VNRecognizedTextObservation inherits from VNRectangleObservation
                    // Use the actual corner points for accurate polygon representation
                    // Vision uses bottom-left origin, convert to top-left origin
                    let topLeft = CGPoint(
                        x: observation.topLeft.x * imageWidth,
                        y: (1 - observation.topLeft.y) * imageHeight
                    )
                    let topRight = CGPoint(
                        x: observation.topRight.x * imageWidth,
                        y: (1 - observation.topRight.y) * imageHeight
                    )
                    let bottomRight = CGPoint(
                        x: observation.bottomRight.x * imageWidth,
                        y: (1 - observation.bottomRight.y) * imageHeight
                    )
                    let bottomLeft = CGPoint(
                        x: observation.bottomLeft.x * imageWidth,
                        y: (1 - observation.bottomLeft.y) * imageHeight
                    )

                    // Create polygon points array
                    let points: [[String: Double]] = [
                        ["x": Double(topLeft.x), "y": Double(topLeft.y)],
                        ["x": Double(topRight.x), "y": Double(topRight.y)],
                        ["x": Double(bottomRight.x), "y": Double(bottomRight.y)],
                        ["x": Double(bottomLeft.x), "y": Double(bottomLeft.y)]
                    ]

                    let characterEntries = self.characterEntries(
                        for: topCandidate,
                        imageWidth: imageWidth,
                        imageHeight: imageHeight
                    )

                    detectedTexts.append([
                        "text": topCandidate.string,
                        "confidence": topCandidate.confidence,
                        "points": points,
                        "characters": characterEntries
                    ])
                }
            }
            self.register(request, requestId: requestId)

            // Configure request for best accuracy
            request.recognitionLevel = .accurate
            request.minimumTextHeight = 0.01
            request.usesLanguageCorrection = true

            // Use automatic language detection if available
            var configuredRevision = request.revision
            var autoLanguageEnabled = false
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
                autoLanguageEnabled = request.automaticallyDetectsLanguage
                request.revision = VNRecognizeTextRequestRevision3
                configuredRevision = request.revision
            } else {
                // Default to English for older iOS versions
                request.recognitionLanguages = ["en-US"]
            }
            MobileOcrPlugin.logDebug(
                "detectText request configured file=\(fileName)"
                + " revision=\(configuredRevision)"
                + " autoLanguage=\(autoLanguageEnabled)"
            )

            // Perform the request
            do {
                try requestHandler.perform([request])
            } catch {
                callbackError = error
            }
            let requestWasCancelled = self.finishRequest(
                request,
                requestId: requestId
            )
            if requestWasCancelled {
                DispatchQueue.main.async {
                    result(FlutterError(code: "CANCELLED",
                                       message: "OCR request was cancelled",
                                       details: nil))
                }
                return
            }
            if let callbackError = callbackError {
                DispatchQueue.main.async {
                    result(FlutterError(code: "RECOGNITION_ERROR",
                                       message: "Text recognition failed",
                                       details: callbackError.localizedDescription))
                }
                return
            }
            MobileOcrPlugin.logDebug(
                "detectText finished file=\(fileName)"
                + " observations=\(observationCount)"
                + " kept=\(detectedTexts.count)"
                + " droppedLowConf=\(discardedLowConfidence)"
                + " samples=\(previewSamples.joined(separator: " | "))"
            )

            // Helper function to calculate bounding rect
            func boundingRect(for pointMaps: [[String: Double]]) -> CGRect? {
                guard let firstX = pointMaps.first?["x"], let firstY = pointMaps.first?["y"] else {
                    return nil
                }
                var minX = firstX, maxX = firstX, minY = firstY, maxY = firstY
                for point in pointMaps {
                    guard let x = point["x"], let y = point["y"] else { continue }
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
                return CGRect(x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
            }

            // Sort results by position (top to bottom, left to right)
            detectedTexts.sort { first, second in
                guard
                    let firstPoints = first["points"] as? [[String: Double]],
                    let secondPoints = second["points"] as? [[String: Double]],
                    let firstRect = boundingRect(for: firstPoints),
                    let secondRect = boundingRect(for: secondPoints)
                else {
                    return false
                }

                // Sort by vertical position, then horizontal
                if abs(firstRect.minY - secondRect.minY) > 10 {
                    return firstRect.minY < secondRect.minY
                }
                return firstRect.minX < secondRect.minX
            }

            // Return results on main thread
            DispatchQueue.main.async {
                result([
                    "blocks": detectedTexts,
                    "imageWidth": cgImage.width,
                    "imageHeight": cgImage.height
                ] as [String: Any])
            }
        }
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    private func characterEntries(for candidate: VNRecognizedText,
                                  imageWidth: CGFloat,
                                  imageHeight: CGFloat) -> [[String: Any]] {
        var entries: [[String: Any]] = []
        var start = candidate.string.startIndex
        while start < candidate.string.endIndex {
            let end = candidate.string.index(after: start)
            let range = start..<end
            if let observation = try? candidate.boundingBox(for: range) {
                let points: [[String: Double]] = [
                    ["x": Double(observation.topLeft.x * imageWidth),
                     "y": Double((1 - observation.topLeft.y) * imageHeight)],
                    ["x": Double(observation.topRight.x * imageWidth),
                     "y": Double((1 - observation.topRight.y) * imageHeight)],
                    ["x": Double(observation.bottomRight.x * imageWidth),
                     "y": Double((1 - observation.bottomRight.y) * imageHeight)],
                    ["x": Double(observation.bottomLeft.x * imageWidth),
                     "y": Double((1 - observation.bottomLeft.y) * imageHeight)]
                ]
                entries.append([
                    "text": String(candidate.string[range]),
                    "confidence": candidate.confidence,
                    "points": points
                ])
            }
            start = end
        }
        return entries
    }

    // Helper to validate if text looks meaningful (not just symbols/noise)
    private func isValidText(_ text: String) -> Bool {
        // Remove whitespace and check length
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        let alphanumericSet = CharacterSet.alphanumerics

        // Look for at least one sequence of 3+ consecutive alphanumeric characters
        // This allows "198", "abc", "P@ss123" but rejects noise like "*•/• ; 41'4.•/4"
        var consecutiveCount = 0
        for scalar in trimmed.unicodeScalars {
            if alphanumericSet.contains(scalar) {
                consecutiveCount += 1
                if consecutiveCount >= 3 {
                    return true  // Found a word-like sequence
                }
            } else {
                consecutiveCount = 0
            }
        }

        return false
    }

    private func quickDetectText(imagePath: String,
                                 minConfidence: Float,
                                 result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async(execute: { [weak self] in
            guard let self = self else { return }
            let fileName = URL(fileURLWithPath: imagePath).lastPathComponent

            guard FileManager.default.fileExists(atPath: imagePath) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_NOT_FOUND",
                                       message: "Image file does not exist",
                                       details: nil))
                }
                return
            }
            guard let image = UIImage(contentsOfFile: imagePath) else {
                MobileOcrPlugin.logDebug("hasText load failure for \(fileName)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to load image from path",
                                       details: nil))
                }
                return
            }

            // Downscale image for faster hasText detection
            // Use max dimension of 1024 pixels for quick detection
            let maxDimension: CGFloat = 1024
            var targetSize = image.size

            if image.size.width > maxDimension || image.size.height > maxDimension {
                let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
                targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            }
            MobileOcrPlugin.logDebug(
                "hasText start file=\(fileName)"
                + " originalSize=\(Int(image.size.width))x\(Int(image.size.height))"
                + " scaledSize=\(Int(targetSize.width))x\(Int(targetSize.height))"
                + " minConf=\(String(format: "%.2f", minConfidence))"
            )

            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let fixedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }

            guard let cgImage = fixedImage.cgImage else {
                MobileOcrPlugin.logDebug("hasText CGImage missing for \(fileName)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_DECODE_ERROR",
                                       message: "Failed to get CGImage",
                                       details: nil))
                }
                return
            }

            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            var hasValidText = false
            var observationCount = 0
            var acceptedCandidates = 0
            var rejectedByConfidence = 0
            var rejectedByValidation = 0
            var validationSamples: [String] = []
            var callbackError: Error?

            // Use VNRecognizeTextRequest (same as detectText) instead of VNDetectTextRectanglesRequest
            // This ensures consistency between hasText and detectText
            let request = VNRecognizeTextRequest { (request, error) in
                if let error = error {
                    callbackError = error
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    return
                }
                observationCount = observations.count

                // Check if any recognized text meets the confidence threshold and is valid
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }

                    let isValid = self.isValidText(topCandidate.string)

                    if topCandidate.confidence >= minConfidence {
                        if isValid {
                            acceptedCandidates += 1
                            hasValidText = true
                            if validationSamples.count < 3 {
                                let sanitized = topCandidate.string
                                    .replacingOccurrences(of: "\n", with: " ")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                validationSamples.append(
                                    "\(String(format: "%.2f", topCandidate.confidence))|\(sanitized)"
                                )
                            }
                            break  // Found at least one valid text with high confidence
                        } else {
                            rejectedByValidation += 1
                        }
                    } else {
                        rejectedByConfidence += 1
                    }
                }
            }

            // Use same settings as detectText for consistent confidence scores
            request.recognitionLevel = .accurate
            request.minimumTextHeight = 0.01
            request.usesLanguageCorrection = true

            // Use automatic language detection if available
            var configuredRevision = request.revision
            var autoLanguageEnabled = false
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
                autoLanguageEnabled = request.automaticallyDetectsLanguage
                request.revision = VNRecognizeTextRequestRevision3
                configuredRevision = request.revision
            } else {
                request.recognitionLanguages = ["en-US"]
            }
            MobileOcrPlugin.logDebug(
                "hasText request configured file=\(fileName)"
                + " revision=\(configuredRevision)"
                + " autoLanguage=\(autoLanguageEnabled)"
            )

            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DETECTION_ERROR",
                                       message: "Failed to perform text detection",
                                       details: error.localizedDescription))
                }
                return
            }
            if let callbackError = callbackError {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DETECTION_ERROR",
                                       message: "Text detection failed",
                                       details: callbackError.localizedDescription))
                }
                return
            }
            MobileOcrPlugin.logDebug(
                "hasText finished file=\(fileName)"
                + " observations=\(observationCount)"
                + " validMatches=\(acceptedCandidates)"
                + " rejectedLowConf=\(rejectedByConfidence)"
                + " rejectedValidation=\(rejectedByValidation)"
                + " result=\(hasValidText)"
                + " samples=\(validationSamples.joined(separator: " | "))"
            )

            DispatchQueue.main.async {
                result(hasValidText)
            }
        })
    }

    private func handleCancelRequest(call: FlutterMethodCall,
                                     result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let requestId = arguments["requestId"] as? String,
              !requestId.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENT",
                               message: "Request ID is required",
                               details: nil))
            return
        }
        requestLock.lock()
        let request = activeRequests.removeValue(forKey: requestId)
        cancelledRequestIds.insert(requestId)
        requestLock.unlock()
        request?.cancel()
        result(nil)
    }

    private func register(_ request: VNRequest, requestId: String?) {
        guard let requestId = requestId else { return }
        requestLock.lock()
        cancelledRequestIds.remove(requestId)
        let previous = activeRequests.updateValue(request, forKey: requestId)
        requestLock.unlock()
        previous?.cancel()
    }

    private func finishRequest(_ request: VNRequest, requestId: String?) -> Bool {
        guard let requestId = requestId else { return false }
        requestLock.lock()
        if activeRequests[requestId] === request {
            activeRequests.removeValue(forKey: requestId)
        }
        let wasCancelled = cancelledRequestIds.remove(requestId) != nil
        requestLock.unlock()
        return wasCancelled
    }

    private static func logDebug(_ message: String) {
        #if DEBUG
        print("[MobileOCR] \(message)")
        #endif
    }

}
