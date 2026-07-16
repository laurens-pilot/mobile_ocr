import 'dart:ui';

/// A detector-only text candidate in oriented image coordinates.
class TextRegion {
  final double confidence;
  final List<Offset> points;

  const TextRegion({required this.confidence, required this.points});

  Rect get boundingBox {
    if (points.isEmpty) {
      return Rect.zero;
    }

    var left = points.first.dx;
    var top = points.first.dy;
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      if (point.dx < left) left = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dx > right) right = point.dx;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  factory TextRegion.fromMap(Map<dynamic, dynamic> map) {
    final points = (map['points'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (point) => Offset(
            (point['x'] as num).toDouble(),
            (point['y'] as num).toDouble(),
          ),
        )
        .toList(growable: false);
    return TextRegion(
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      points: points,
    );
  }
}

/// Detector-only output. It intentionally contains no recognized strings.
class TextRegionDetectionResult {
  final List<TextRegion> regions;
  final Size imageSize;

  const TextRegionDetectionResult({
    required this.regions,
    required this.imageSize,
  });

  factory TextRegionDetectionResult.fromMap(Map<dynamic, dynamic> map) {
    final regions = (map['regions'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(TextRegion.fromMap)
        .toList(growable: false);
    return TextRegionDetectionResult(
      regions: regions,
      imageSize: Size(
        (map['imageWidth'] as num?)?.toDouble() ?? 0,
        (map['imageHeight'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}
