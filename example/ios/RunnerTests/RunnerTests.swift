import Flutter
@testable import mobile_ocr
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testTraditionalChineseRegionSelectsTraditionalScript() {
    let selected = RecognitionLanguageSelector.select(
      preferredLanguages: ["zh-HK"],
      supportedLanguages: ["zh-Hans", "zh-Hant", "en-US"]
    )

    XCTAssertEqual(selected, ["zh-Hant", "en-US"])
  }

  func testExplicitTraditionalScriptSelectsTraditionalScript() {
    let selected = RecognitionLanguageSelector.select(
      preferredLanguages: ["zh-Hant-HK"],
      supportedLanguages: ["zh-Hans", "zh-Hant", "en-US"]
    )

    XCTAssertEqual(selected, ["zh-Hant", "en-US"])
  }

  func testSimplifiedChineseRegionSelectsSimplifiedScript() {
    let selected = RecognitionLanguageSelector.select(
      preferredLanguages: ["zh-CN"],
      supportedLanguages: ["zh-Hant", "zh-Hans", "en-US"]
    )

    XCTAssertEqual(selected, ["zh-Hans", "en-US"])
  }
}
