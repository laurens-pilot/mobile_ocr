class OcrException implements Exception {
  final String code;
  final String message;
  final Object? details;

  const OcrException({required this.code, required this.message, this.details});

  @override
  String toString() => 'OcrException($code, $message)';
}
