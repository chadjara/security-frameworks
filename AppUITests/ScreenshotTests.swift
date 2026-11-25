import XCTest

/// Captures design-system screens in light, dark, and accessibility text sizes so they can be
/// reviewed without Xcode. CI passes TEST_RUNNER_SCREENSHOT_DIR, which reaches the runner as
/// SCREENSHOT_DIR; screenshots are also attached to the result bundle. One test per screen keeps
/// retries short.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func shoot(_ screen: String, scheme: String = "light", textSize: String? = nil, pages: Int,
                       waitForText: String? = nil) {
        var args = ["-dsColorScheme", scheme, "-dsScreen", screen]
        if let textSize { args += ["-dsDynamicType", textSize] }
        let app = launchApp(args)
        guard waitForScreen(app, "screen.\(screen)") else { return }
        if let waitForText {
            XCTAssertTrue(app.staticTexts[waitForText].waitForExistence(timeout: UITimeout.work),
                          "\"\(waitForText)\" did not appear")
        }
        let name = [screen, scheme, textSize].compactMap { $0 }.joined(separator: "-")
        capture(name, pages: pages, scroll: element(app, "screen.\(screen)"))
    }

    @MainActor func testTypeSpecimenLight() { shoot("typeSpecimen", pages: 4) }
    @MainActor func testTypeSpecimenDark() { shoot("typeSpecimen", scheme: "dark", pages: 4) }
    @MainActor func testTypeSpecimenAccessibilitySize() { shoot("typeSpecimen", textSize: "ax3", pages: 3) }
    @MainActor func testColorTokensLight() { shoot("colorTokens", pages: 2) }
    @MainActor func testColorTokensDark() { shoot("colorTokens", scheme: "dark", pages: 2) }
    @MainActor func testComponentsLight() { shoot("components", pages: 3) }
    @MainActor func testComponentsDark() { shoot("components", scheme: "dark", pages: 3) }

    @MainActor
    func testContentValidation() {
        shoot("content", pages: 3, waitForText: "All content passed validation")
    }
}
