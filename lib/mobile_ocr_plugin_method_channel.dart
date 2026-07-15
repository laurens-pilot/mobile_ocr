import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mobile_ocr_plugin_platform_interface.dart';
import 'models/ocr_model.dart';

/// An implementation of [MobileOcrPlatform] that uses method channels.
class MethodChannelMobileOcr extends MobileOcrPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mobile_ocr');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<Map<dynamic, dynamic>> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    final result = await methodChannel
        .invokeMapMethod<dynamic, dynamic>('detectText', {
          'imagePath': imagePath,
          'includeAllConfidenceScores': includeAllConfidenceScores,
          'requestId': requestId,
        });
    return result ?? const {};
  }

  @override
  Future<Map<dynamic, dynamic>> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    final result = await methodChannel.invokeMapMethod<dynamic, dynamic>(
      'detectTextRegions',
      {'imagePath': imagePath, 'requestId': requestId},
    );
    return result ?? const {};
  }

  @override
  Future<void> cancelRequest(String requestId) {
    return methodChannel.invokeMethod<void>('cancelRequest', {
      'requestId': requestId,
    });
  }

  @override
  Future<bool> hasText({required String imagePath}) async {
    final result = await methodChannel.invokeMethod<bool>('hasText', {
      'imagePath': imagePath,
    });
    return result ?? false;
  }

  @override
  Future<Map<dynamic, dynamic>> prepareModels({
    required Set<OcrModelComponent> components,
  }) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'prepareModels',
      {'components': components.map((component) => component.name).toList()},
    );
    return result ?? {};
  }

  @override
  Future<Map<dynamic, dynamic>> getModelAvailability() async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'getModelAvailability',
    );
    return result ?? {};
  }
}
