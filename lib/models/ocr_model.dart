enum OcrModelComponent { detector, recognizer }

class OcrModelAvailability {
  final bool detectorReady;
  final bool recognizerReady;
  final String? version;

  const OcrModelAvailability({
    required this.detectorReady,
    required this.recognizerReady,
    this.version,
  });

  factory OcrModelAvailability.fromMap(Map<dynamic, dynamic> map) {
    return OcrModelAvailability(
      detectorReady: map['detectorReady'] == true,
      recognizerReady: map['recognizerReady'] == true,
      version: map['version'] as String?,
    );
  }
}
