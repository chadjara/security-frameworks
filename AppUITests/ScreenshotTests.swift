import XCTest

/// Captures design-system screens in light, dark, and accessibility text sizes so they can be
/// reviewed without Xcode. CI passes TEST_RUNNER_SCREENSHOT_DIR, which reaches the runner as
/// SCREENSHOT_DIR; screenshots are also attached to the result bundle.
final class ScreenshotTests: XCTestCase {
    struct Shot {
        let screen: String
        let scheme: String
        let textSize: String?
        let pages: Int
    }

    static let shots: [Shot] = [
        Shot(screen: "typeSpecimen", scheme: "light", textSize: nil, pages: 4),
        Shot(screen: "typeSpecimen", scheme: "dark", textSize: nil, pages: 4),
        Shot(screen: "typeSpecimen", scheme: "light", textSize: "ax3", pages: 3),
        Shot(screen: "colorTokens", scheme: "light", textSize: nil, pages: 2),
        Shot(screen: "colorTokens", scheme: "dark", textSize: nil, pages: 2),
        Shot(screen: "components", scheme: "light", textSize: nil, pages: 3),
        Shot(screen: "components", scheme: "dark", textSize: nil, pages: 3),
        Shot(screen: "content", scheme: "light", textSize: nil, pages: 3),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureDesignSystemScreens() throws {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        for shot in Self.shots {
            let app = XCUIApplication()
            app.launchArguments = ["-dsColorScheme", shot.scheme, "-dsScreen", shot.screen]
            if let size = shot.textSize { app.launchArguments += ["-dsDynamicType", size] }
            app.launch()

            let root = app.descendants(matching: .any).matching(identifier: "screen.\(shot.screen)").firstMatch
            XCTAssertTrue(root.waitForExistence(timeout: 60), "\(shot.screen) did not appear")
            if shot.screen == "content" {
                let done = app.staticTexts["All content passed validation"]
                XCTAssertTrue(done.waitForExistence(timeout: 60), "content validation did not finish")
            }

            let base = [device, shot.screen, shot.scheme, shot.textSize].compactMap { $0 }.joined(separator: "-")
            for page in 1...shot.pages {
                if page > 1 {
                    root.swipeUp(velocity: .slow)
                }
                Thread.sleep(forTimeInterval: 0.8)
                capture(name: "\(base)-\(page)")
            }
            app.terminate()
        }
    }

    @MainActor
    func testNavigationReachesEveryScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-dsScreen", "typeSpecimen"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "screen.typeSpecimen").firstMatch
            .waitForExistence(timeout: 60))
    }

    @MainActor
    private func capture(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
