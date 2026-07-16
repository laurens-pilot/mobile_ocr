import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_ocr/mobile_ocr_plugin.dart';

const bool _runNativeOcrSmoke = bool.fromEnvironment('OCR_NATIVE_SMOKE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('getPlatformVersion test', (WidgetTester tester) async {
    final MobileOcr plugin = MobileOcr();
    final String? version = await plugin.getPlatformVersion();
    expect(version?.isNotEmpty, true);
  });

  testWidgets(
    'detector-only and full OCR run on a bundled sample',
    (WidgetTester tester) async {
      final plugin = MobileOcr();
      final data = await rootBundle.load('assets/test_ocr/ocr_test.jpeg');
      final image = File('${Directory.systemTemp.path}/ocr_test.jpeg');
      await image.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      addTearDown(() async {
        if (await image.exists()) {
          await image.delete();
        }
      });

      final detectorPreparation = Stopwatch()..start();
      final detectorStatus = await plugin.prepareModels(
        components: {OcrModelComponent.detector},
      );
      detectorPreparation.stop();
      expect(detectorStatus.isReady, isTrue);

      final availability = await plugin.getModelAvailability();
      expect(availability.detectorReady, isTrue);

      const regionRequestId = 'native-smoke-region-cancel';
      final regionCancellation = Stopwatch()..start();
      final cancelledRegions = plugin.detectTextRegions(
        imagePath: image.path,
        requestId: regionRequestId,
      );
      await plugin.cancelRequest(regionRequestId);
      await expectLater(
        cancelledRegions,
        throwsA(
          isA<OcrException>().having(
            (error) => error.code,
            'code',
            'CANCELLED',
          ),
        ),
      );
      regionCancellation.stop();

      final regionDetection = Stopwatch()..start();
      final regions = await plugin.detectTextRegions(imagePath: image.path);
      regionDetection.stop();
      expect(regions.imageSize.width, greaterThan(0));
      expect(regions.imageSize.height, greaterThan(0));
      expect(regions.regions, isNotEmpty);

      final fullPreparation = Stopwatch()..start();
      final fullStatus = await plugin.prepareModels();
      fullPreparation.stop();
      expect(fullStatus.isReady, isTrue);

      const recognitionRequestId = 'native-smoke-recognition-cancel';
      final recognitionCancellation = Stopwatch()..start();
      final cancelledRecognition = plugin.detectText(
        imagePath: image.path,
        requestId: recognitionRequestId,
      );
      await plugin.cancelRequest(recognitionRequestId);
      await expectLater(
        cancelledRecognition,
        throwsA(
          isA<OcrException>().having(
            (error) => error.code,
            'code',
            'CANCELLED',
          ),
        ),
      );
      recognitionCancellation.stop();

      final recognition = Stopwatch()..start();
      final result = await plugin.detectText(imagePath: image.path);
      recognition.stop();
      expect(result.blocks, isNotEmpty);
      expect(
        result.blocks.map((block) => block.text).join(' ').toLowerCase(),
        contains('restaurant'),
      );

      // Printed values are retained by `flutter test -d` for device profiling.
      // ignore: avoid_print
      print(
        'OCR_SMOKE detectorPrepareMs=${detectorPreparation.elapsedMilliseconds} '
        'regionCancelMs=${regionCancellation.elapsedMilliseconds} '
        'regionsMs=${regionDetection.elapsedMilliseconds} '
        'regionCount=${regions.regions.length} '
        'fullPrepareMs=${fullPreparation.elapsedMilliseconds} '
        'recognitionCancelMs=${recognitionCancellation.elapsedMilliseconds} '
        'recognitionMs=${recognition.elapsedMilliseconds} '
        'blockCount=${result.blocks.length}',
      );
    },
    skip: !_runNativeOcrSmoke,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
