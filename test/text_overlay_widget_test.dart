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
}
