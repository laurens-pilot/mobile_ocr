import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_ocr/mobile_ocr_plugin.dart';

const bool _runNativeOcrSmoke = bool.fromEnvironment('OCR_NATIVE_SMOKE');
const bool _runNativeOcrFixtures = bool.fromEnvironment('OCR_NATIVE_FIXTURES');
const bool _printNativeOcrFixtureText = bool.fromEnvironment(
  'OCR_NATIVE_FIXTURE_VERBOSE',
);

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

  testWidgets(
    'bundled OCR fixtures retain stable text and geometry',
    (WidgetTester tester) async {
      final plugin = MobileOcr();
      final preparation = await plugin.prepareModels();
      expect(preparation.isReady, isTrue);

      final manifestData = await rootBundle.loadString(
        'assets/test_ocr/ground_truth.json',
      );
      final manifest = jsonDecode(manifestData) as Map<String, dynamic>;
      final failures = <String>[];

      for (final fixture in manifest.entries) {
        final fileName = fixture.key;
        final expectation = fixture.value as Map<String, dynamic>;
        final data = await rootBundle.load('assets/test_ocr/$fileName');
        final image = File(
          '${Directory.systemTemp.path}/mobile_ocr_fixture_$fileName',
        );
        await image.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );

        try {
          final stopwatch = Stopwatch()..start();
          final result = await plugin.detectText(imagePath: image.path);
          stopwatch.stop();
          final recognizedText = result.blocks
              .map((block) => block.text)
              .join(' ');
          final normalizedText = _normalizeOcrText(recognizedText);
          final requiredTexts = <String>[
            ...(expectation['requiredTexts'] as List<dynamic>).cast<String>(),
            ...(expectation['${Platform.operatingSystem}RequiredTexts']
                        as List<dynamic>? ??
                    const <dynamic>[])
                .cast<String>(),
          ];
          final missingTexts = requiredTexts
              .where(
                (text) => !normalizedText.contains(_normalizeOcrText(text)),
              )
              .toList(growable: false);
          final minimumBlocks = expectation['minimumBlocks'] as int;

          if (result.blocks.length < minimumBlocks) {
            failures.add(
              '$fileName: expected at least $minimumBlocks blocks, '
              'found ${result.blocks.length}',
            );
          }
          if (missingTexts.isNotEmpty) {
            failures.add(
              '$fileName: missing stable text $missingTexts; '
              'recognized "$recognizedText"',
            );
          }
          _validateResultGeometry(fileName, result, failures);

          // ignore: avoid_print
          print(
            'OCR_FIXTURE platform=${Platform.operatingSystem} '
            'name=$fileName elapsedMs=${stopwatch.elapsedMilliseconds} '
            'blocks=${result.blocks.length} missing=${missingTexts.length}',
          );
          if (_printNativeOcrFixtureText) {
            // ignore: avoid_print
            print('OCR_FIXTURE_TEXT name=$fileName text="$recognizedText"');
          }
        } catch (error, stackTrace) {
          failures.add('$fileName: threw $error\n$stackTrace');
        } finally {
          if (await image.exists()) {
            await image.delete();
          }
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    },
    skip: !_runNativeOcrFixtures,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

String _normalizeOcrText(String text) {
  return text.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    '',
  );
}

void _validateResultGeometry(
  String fileName,
  TextDetectionResult result,
  List<String> failures,
) {
  final width = result.imageSize.width;
  final height = result.imageSize.height;
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    failures.add('$fileName: invalid image size ${result.imageSize}');
    return;
  }

  final xTolerance = width * 0.05;
  final yTolerance = height * 0.05;
  for (var blockIndex = 0; blockIndex < result.blocks.length; blockIndex++) {
    final block = result.blocks[blockIndex];
    if (block.text.trim().isEmpty) {
      failures.add('$fileName: block $blockIndex has no text');
    }
    if (!block.confidence.isFinite ||
        block.confidence < 0 ||
        block.confidence > 1) {
      failures.add(
        '$fileName: block $blockIndex has invalid confidence '
        '${block.confidence}',
      );
    }
    _validatePolygon(
      fileName: fileName,
      label: 'block $blockIndex',
      points: block.points,
      width: width,
      height: height,
      xTolerance: xTolerance,
      yTolerance: yTolerance,
      failures: failures,
      requireArea: true,
    );

    for (
      var characterIndex = 0;
      characterIndex < block.characters.length;
      characterIndex++
    ) {
      final character = block.characters[characterIndex];
      if (character.text.isEmpty) {
        failures.add(
          '$fileName: block $blockIndex character $characterIndex has no text',
        );
      }
      if (!character.confidence.isFinite ||
          character.confidence < 0 ||
          character.confidence > 1) {
        failures.add(
          '$fileName: block $blockIndex character $characterIndex has '
          'invalid confidence ${character.confidence}',
        );
      }
      _validatePolygon(
        fileName: fileName,
        label: 'block $blockIndex character $characterIndex',
        points: character.points,
        width: width,
        height: height,
        xTolerance: xTolerance,
        yTolerance: yTolerance,
        failures: failures,
        requireArea: character.text.trim().isNotEmpty,
      );
    }
  }
}

void _validatePolygon({
  required String fileName,
  required String label,
  required List<Offset> points,
  required double width,
  required double height,
  required double xTolerance,
  required double yTolerance,
  required List<String> failures,
  required bool requireArea,
}) {
  if (points.length < 4) {
    failures.add('$fileName: $label has ${points.length} polygon points');
    return;
  }

  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = double.negativeInfinity;
  var maxY = double.negativeInfinity;
  for (final point in points) {
    if (!point.dx.isFinite || !point.dy.isFinite) {
      failures.add('$fileName: $label has non-finite point $point');
    } else if (point.dx < -xTolerance ||
        point.dx > width + xTolerance ||
        point.dy < -yTolerance ||
        point.dy > height + yTolerance) {
      failures.add(
        '$fileName: $label point $point exceeds ${width}x$height bounds',
      );
    }
    minX = point.dx < minX ? point.dx : minX;
    minY = point.dy < minY ? point.dy : minY;
    maxX = point.dx > maxX ? point.dx : maxX;
    maxY = point.dy > maxY ? point.dy : maxY;
  }
  if (requireArea &&
      minX.isFinite &&
      minY.isFinite &&
      maxX.isFinite &&
      maxY.isFinite &&
      (maxX <= minX || maxY <= minY)) {
    failures.add('$fileName: $label has degenerate geometry');
  }
}
