import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ocr/models/text_block.dart';
import 'package:mobile_ocr/widgets/text_overlay_widget.dart';

void main() {
  testWidgets('selects words using native grapheme box indices', (
    WidgetTester tester,
  ) async {
    final controller = TextOverlayController();
    const characters = <String>['น้ำ', ' ', 'a', 'b', 'c'];
    final boxes = <CharacterBox>[
      for (int index = 0; index < characters.length; index++)
        CharacterBox(
          text: characters[index],
          confidence: 1,
          points: <Offset>[
            Offset(20 + index * 40, 40),
            Offset(60 + index * 40, 40),
            Offset(60 + index * 40, 70),
            Offset(20 + index * 40, 70),
          ],
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              height: 100,
              child: TextOverlayWidget(
                controller: controller,
                imageSize: const Size(240, 100),
                enableSelectionPreview: true,
                textBlocks: <TextBlock>[
                  TextBlock(
                    text: 'น้ำ abc',
                    confidence: 1,
                    points: const <Offset>[
                      Offset(20, 40),
                      Offset(220, 40),
                      Offset(220, 70),
                      Offset(20, 70),
                    ],
                    characters: boxes,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    controller.selectTextAtPosition(const Offset(160, 55));
    await tester.pumpAndSettle();

    expect(find.text('abc'), findsOneWidget);
  });

  testWidgets('centers the toolbar when all full-screen text is selected', (
    WidgetTester tester,
  ) async {
    final controller = TextOverlayController();
    await _pumpOverlay(
      tester,
      controller: controller,
      imageSize: const Size(400, 800),
      blocks: <TextBlock>[
        _block('Top text', const Rect.fromLTWH(20, 40, 360, 40)),
        _block('Bottom text', const Rect.fromLTWH(20, 720, 360, 40)),
      ],
    );

    expect(controller.selectAllText(), isTrue);
    await tester.pump();

    final toolbarCenter = _toolbarRect(tester).center;
    expect(toolbarCenter.dx, closeTo(200, 4));
    expect(toolbarCenter.dy, closeTo(400, 0.1));
  });

  testWidgets('keeps the full-selection toolbar inside a letterboxed photo', (
    WidgetTester tester,
  ) async {
    final controller = TextOverlayController();
    await _pumpOverlay(
      tester,
      controller: controller,
      imageSize: const Size(400, 400),
      blocks: <TextBlock>[
        _block('Top text', const Rect.fromLTWH(20, 5, 360, 40)),
        _block('Bottom text', const Rect.fromLTWH(20, 355, 360, 40)),
      ],
    );

    expect(controller.selectAllText(), isTrue);
    await tester.pump();

    final toolbarRect = _toolbarRect(tester);
    expect(toolbarRect.center.dx, closeTo(200, 4));
    expect(toolbarRect.center.dy, closeTo(400, 0.1));
    expect(
      const Rect.fromLTWH(0, 200, 400, 400).contains(toolbarRect.topLeft),
      isTrue,
    );
    expect(
      const Rect.fromLTWH(0, 200, 400, 400).contains(toolbarRect.bottomRight),
      isTrue,
    );
  });

  testWidgets('keeps a partial-selection toolbar next to its text', (
    WidgetTester tester,
  ) async {
    final controller = TextOverlayController();
    await _pumpOverlay(
      tester,
      controller: controller,
      imageSize: const Size(400, 800),
      blocks: <TextBlock>[
        _block('Selected text', const Rect.fromLTWH(40, 600, 320, 40)),
        _block('Other text', const Rect.fromLTWH(40, 700, 320, 40)),
      ],
    );

    controller.selectTextAtPosition(const Offset(100, 620));
    await tester.pump();

    expect(_toolbarRect(tester).bottom, lessThan(600));
  });

  testWidgets('selected highlights do not block tap-to-clear handling', (
    WidgetTester tester,
  ) async {
    final controller = TextOverlayController();
    await _pumpOverlay(
      tester,
      controller: controller,
      imageSize: const Size(400, 800),
      blocks: <TextBlock>[
        _block('Top text', const Rect.fromLTWH(20, 80, 360, 40)),
        _block('Bottom text', const Rect.fromLTWH(20, 680, 360, 40)),
      ],
    );

    expect(controller.selectAllText(), isTrue);
    await tester.pump();

    expect(
      controller.isPointOnInteractiveSelectionUi(const Offset(200, 100)),
      isFalse,
    );
    expect(
      controller.isPointOnInteractiveSelectionUi(
        tester.getCenter(find.widgetWithText(TextButton, 'Copy')),
      ),
      isTrue,
    );
  });
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required TextOverlayController controller,
  required Size imageSize,
  required List<TextBlock> blocks,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TextOverlayWidget(
          controller: controller,
          imageSize: imageSize,
          textBlocks: blocks,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TextBlock _block(String text, Rect rect) {
  return TextBlock(
    text: text,
    confidence: 1,
    characters: const <CharacterBox>[],
    points: <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ],
  );
}

Rect _toolbarRect(WidgetTester tester) {
  return tester
      .getRect(find.widgetWithText(TextButton, 'Copy'))
      .expandToInclude(
        tester.getRect(find.widgetWithText(TextButton, 'Select all')),
      );
}
