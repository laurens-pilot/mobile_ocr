import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ocr/src/text_reading_order.dart';

void main() {
  TextReadingOrderBlock block(
    int index,
    double left,
    double top, {
    double width = 80,
    double height = 20,
    String text = 'text',
  }) {
    return TextReadingOrderBlock(
      index: index,
      bounds: Rect.fromLTWH(left, top, width, height),
      text: text,
    );
  }

  test('uses row order for a single column', () {
    final order = orderTextBlocksForReading([
      block(2, 10, 80),
      block(0, 10, 20),
      block(1, 10, 50),
    ]);

    expect(order, [0, 1, 2]);
  });

  test('reads each column before advancing to the next', () {
    final order = orderTextBlocksForReading([
      block(0, 10, 10),
      block(1, 120, 12),
      block(2, 10, 40),
      block(3, 120, 42),
    ]);

    expect(order, [0, 2, 1, 3]);
  });

  test('keeps spanning headings and footers around columns', () {
    final order = orderTextBlocksForReading([
      block(0, 10, 0, width: 190),
      block(1, 10, 30),
      block(2, 120, 32),
      block(3, 10, 60),
      block(4, 120, 62),
      block(5, 10, 100, width: 190),
    ]);

    expect(order, [0, 1, 3, 2, 4, 5]);
  });

  test('keeps column blocks that overlap a spanning heading', () {
    final order = orderTextBlocksForReading([
      block(0, 10, 0, width: 190, height: 40),
      block(1, 10, 20),
      block(2, 120, 22),
      block(3, 10, 60),
      block(4, 120, 62),
    ]);

    expect(order, [0, 1, 3, 2, 4]);
  });

  test('reads predominantly RTL columns from right to left', () {
    final order = orderTextBlocksForReading([
      block(0, 10, 10, text: 'مرحبا'),
      block(1, 120, 12, text: 'العالم'),
      block(2, 10, 40, text: 'نص'),
      block(3, 120, 42, text: 'عربي'),
    ]);

    expect(order, [1, 3, 0, 2]);
  });

  test('does not treat vertically separate indents as columns', () {
    final order = orderTextBlocksForReading([
      block(0, 10, 10),
      block(1, 120, 80),
      block(2, 120, 110),
    ]);

    expect(order, [0, 1, 2]);
  });
}
