import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ocr/mobile_ocr_plugin_method_channel.dart';
import 'package:mobile_ocr/mobile_ocr_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelMobileOcr platform = MethodChannelMobileOcr();
  const MethodChannel channel = MethodChannel('mobile_ocr');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'detectText':
              return {
                'blocks': [
                  {
                    'text': 'hello',
                    'confidence': 0.9,
                    'points': [
                      {'x': 1.0, 'y': 2.0},
                      {'x': 11.0, 'y': 2.0},
                      {'x': 11.0, 'y': 7.0},
                      {'x': 1.0, 'y': 7.0},
                    ],
                  },
                ],
                'imageWidth': 100,
                'imageHeight': 200,
              };
            case 'hasText':
              return true;
            case 'detectTextRegions':
              return {
                'regions': [
                  {
                    'confidence': 0.75,
                    'points': [
                      {'x': 1.0, 'y': 2.0},
                      {'x': 11.0, 'y': 2.0},
                      {'x': 11.0, 'y': 7.0},
                      {'x': 1.0, 'y': 7.0},
                    ],
                  },
                ],
                'imageWidth': 100,
                'imageHeight': 200,
              };
            case 'getModelAvailability':
              return {
                'detectorReady': true,
                'recognizerReady': false,
                'version': 'test',
              };
            case 'prepareModels':
              return {'isReady': true, 'version': 'test', 'modelPath': '/tmp'};
            case 'cancelRequest':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('detectText forwards path', () async {
    final result = await platform.detectText(
      imagePath: '/tmp/test.png',
      includeAllConfidenceScores: true,
    );
    final blocks = result['blocks'] as List;
    expect(blocks, hasLength(1));
    expect((blocks.first as Map)['text'], 'hello');
    expect((blocks.first as Map)['points'], isNotEmpty);
    expect(result['imageWidth'], 100);
    expect(result['imageHeight'], 200);
  });

  test('hasText returns boolean result', () async {
    final result = await platform.hasText(imagePath: '/tmp/test.png');
    expect(result, isTrue);
  });

  test('detectTextRegions forwards path', () async {
    final result = await platform.detectTextRegions(imagePath: '/tmp/test.png');
    expect(result['regions'], hasLength(1));
    expect(result['imageWidth'], 100);
    expect(result['imageHeight'], 200);
  });

  test('getModelAvailability returns component readiness', () async {
    final result = await platform.getModelAvailability();
    expect(result['detectorReady'], isTrue);
    expect(result['recognizerReady'], isFalse);
  });

  test('prepareModels accepts detector-only preparation', () async {
    final result = await platform.prepareModels(
      components: {OcrModelComponent.detector},
    );
    expect(result['isReady'], isTrue);
  });

  test('cancelRequest forwards request identifier', () async {
    await platform.cancelRequest('request-1');
  });
}
