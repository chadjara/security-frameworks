import XCTest

/// App Store screenshots, captured with the sample assessment in light mode. Skipped unless the App
/// Store workflow sets APPSTORE_SCREENSHOTS=1 (passed to the runner as TEST_RUNNER_APPSTORE_SCREENSHOTS).
/// Files are named so they sort in the order they appear on the listing.
final class AppStoreScreenshotTests: XCTestCase {
    private struct Shot {
        let name: String
        let route: String
        let screen: String
        var extra: [String] = []
        /// Swipes before capturing, to show the most useful part of a long screen.
        var swipes = 0
    }

    /// iPhone: one screen at a time, led by the overview.
    private let phoneShots: [Shot] = [
        Shot(name: "01-overview", route: "overview", screen: "screen.overview"),
        Shot(name: "02-requirement", route: "detail:csf-2.0:GV.OC-03", screen: "screen.requirementDetail"),
        Shot(name: "03-questionnaire", route: "questionnaire:sp800-171r3", screen: "screen.questionnaire"),
        Shot(name: "04-requirements", route: "list:sp800-53r5", screen: "screen.requirements"),
        Shot(name: "05-next-steps", route: "nextSteps", screen: "screen.nextSteps"),
        Shot(name: "06-profile", route: "profile:csf-2.0", screen: "screen.csfProfile", extra: ["-uiProfileTab", "summary"]),
        Shot(name: "07-export", route: "export", screen: "screen.export"),
        Shot(name: "08-explorer", route: "explorer", screen: "screen.explorer"),
    ]

    /// iPad: screens where the sidebar, list, and detail are all filled, so no column shows a placeholder.
    private let padShots: [Shot] = [
        Shot(name: "01-requirement", route: "detail:csf-2.0:GV.OC-03", screen: "screen.requirementDetail"),
        Shot(name: "02-questionnaire", route: "questionnaire:sp800-171r3", screen: "screen.questionnaire"),
        Shot(name: "03-profile", route: "profile:csf-2.0", screen: "screen.csfProfile", extra: ["-uiProfileTab", "summary"]),
        Shot(name: "04-related", route: "detail:sp800-171r3:03.01.01", screen: "screen.requirementDetail", swipes: 2),
        Shot(name: "05-preview", route: "preview:sp800-53r5", screen: "screen.frameworkPreview"),
        Shot(name: "06-baseline", route: "scope:sp800-53r5", screen: "screen.scope"),
        Shot(name: "07-export", route: "export", screen: "screen.export"),
    ]

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOTS"] == "1",
                          "App Store screenshots run only from the App Store workflow")
        continueAfterFailure = true
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        for shot in deviceName == "ipad" ? padShots : phoneShots {
            let app = launchApp(["-dsColorScheme", "light", "-uiSeed", "sample", "-uiRoute", shot.route] + shot.extra)
            guard waitForScreen(app, shot.screen) else { continue }
            // Let charts animate in and lazy rows load.
            settle(3)
            for _ in 0..<shot.swipes { list(app, shot.screen).swipeUp(velocity: .slow); settle() }
            save(XCUIScreen.main.screenshot(), as: shot.name)
        }
    }
}
