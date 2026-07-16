# Native OCR fixtures

The bundled fixture suite runs real OCR on a device or simulator:

```sh
flutter test integration_test/plugin_integration_test.dart \
  -d <device-id> \
  --dart-define=OCR_NATIVE_FIXTURES=true
```

Add `--dart-define=OCR_NATIVE_FIXTURE_VERBOSE=true` to print recognized text
while establishing or updating a baseline.

`assets/test_ocr/ground_truth.json` keeps the human transcription in `texts`
for reference. The executable contract uses:

- `requiredTexts`: stable semantic anchors expected on every platform.
- `iosRequiredTexts` and `androidRequiredTexts`: optional engine-specific
  anchors, since iOS Vision and Android ONNX do not produce identical text.
- `minimumBlocks`: a deliberately loose lower bound that avoids coupling the
  test to engine-specific line segmentation.

The test also requires finite, in-bounds polygons for every result and
non-degenerate polygons for blocks and visible characters. Whitespace
characters may have zero-area boxes on some Vision revisions.
