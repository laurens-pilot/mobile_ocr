import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobile_ocr/models/text_block.dart';
import 'package:mobile_ocr/models/text_region.dart';

import 'models/ocr_exception.dart';
import 'models/ocr_model.dart';

import 'mobile_ocr_plugin_platform_interface.dart';

export 'models/ocr_model.dart';
export 'models/ocr_exception.dart';

Future<T> _translatePlatformException<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PlatformException catch (error) {
    throw OcrException(
      code: error.code,
      message: error.message ?? 'OCR operation failed',
      details: error.details,
    );
  }
}

class MobileOcr {
  Future<String?> getPlatformVersion() {
    return MobileOcrPlatform.instance.getPlatformVersion();
  }

  /// Ensure that the native OCR models required on Android are downloaded.
  ///
  /// Downloads any missing files, verifies checksums, and caches them on disk.
  /// Returns a [ModelPreparationStatus] describing the cache status. This call
  /// is a no-op on iOS because it relies on the Vision framework.
  Future<ModelPreparationStatus> prepareModels({
    Set<OcrModelComponent>? components,
  }) async {
    final requestedComponents = components ?? OcrModelComponent.values.toSet();
    final result = await _translatePlatformException(
      () => MobileOcrPlatform.instance.prepareModels(
        components: requestedComponents,
      ),
    );
    return ModelPreparationStatus.fromMap(result);
  }

  /// Read the native OCR model state without downloading anything.
  Future<OcrModelAvailability> getModelAvailability() async {
    final result = await _translatePlatformException(
      MobileOcrPlatform.instance.getModelAvailability,
    );
    return OcrModelAvailability.fromMap(result);
  }

  /// Detect text in an image at the provided file system path.
  ///
  /// [imagePath] must point to a readable PNG or JPEG file.
  /// By default, only returns results with confidence >= 0.8. Set
  /// [includeAllConfidenceScores] to true to include detections down to 0.5.
  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw ArgumentError('Image file does not exist at path: $imagePath');
    }

    final result = await _translatePlatformException(
      () => MobileOcrPlatform.instance.detectText(
        imagePath: file.path,
        includeAllConfidenceScores: includeAllConfidenceScores,
        requestId: requestId,
      ),
    );
    return TextDetectionResult.fromMap(result);
  }

  /// Detect likely text regions without recognizing their contents.
  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw ArgumentError('Image file does not exist at path: $imagePath');
    }

    final result = await _translatePlatformException(
      () => MobileOcrPlatform.instance.detectTextRegions(
        imagePath: file.path,
        requestId: requestId,
      ),
    );
    return TextRegionDetectionResult.fromMap(result);
  }

  /// Cancel an OCR operation previously started with [requestId].
  Future<void> cancelRequest(String requestId) {
    return _translatePlatformException(
      () => MobileOcrPlatform.instance.cancelRequest(requestId),
    );
  }

  /// Quickly determine whether the image contains high-confidence text.
  ///
  /// Returns `true` if at least one detected text block has confidence >= 0.9.
  /// Only the detection stage runs, making this faster than full recognition.
  Future<bool> hasText({required String imagePath}) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw ArgumentError('Image file does not exist at path: $imagePath');
    }

    return _translatePlatformException(
      () => MobileOcrPlatform.instance.hasText(imagePath: file.path),
    );
  }
}

/// Result of a text detection operation, including detected blocks and
/// the source image dimensions.
class TextDetectionResult {
  final List<TextBlock> blocks;
  final Size imageSize;

  TextDetectionResult({required this.blocks, required this.imageSize});

  factory TextDetectionResult.fromMap(Map<dynamic, dynamic> map) {
    final blocksList =
        (map['blocks'] as List?)?.cast<Map<dynamic, dynamic>>() ?? const [];
    final blocks = blocksList.map(TextBlock.fromMap).toList(growable: false);
    final imageWidth = (map['imageWidth'] as num?)?.toDouble() ?? 0.0;
    final imageHeight = (map['imageHeight'] as num?)?.toDouble() ?? 0.0;
    return TextDetectionResult(
      blocks: blocks,
      imageSize: Size(imageWidth, imageHeight),
    );
  }
}

/// Describes the current preparation status of the native OCR model cache.
class ModelPreparationStatus {
  final bool isReady;
  final String? version;
  final String? modelPath;

  ModelPreparationStatus({required this.isReady, this.version, this.modelPath});

  factory ModelPreparationStatus.fromMap(Map<dynamic, dynamic> map) {
    return ModelPreparationStatus(
      isReady: map['isReady'] == true,
      version: map['version'] as String?,
      modelPath: map['modelPath'] as String?,
    );
  }
}
