import XCTest

/// Phase 2 flows and screenshots. Uses an in-memory store with sample data (`-uiSeed sample`)
/// and jumps to screens with `-uiRoute` so captures are reliable.
final class AppFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    @MainActor
    private func launch(route: String?, seed: Bool = true, scheme: String = "light", textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-dsColorScheme", scheme]
        if seed { args += ["-uiSeed", "sample"] } else { args += ["-uiInMemory", "YES"] }
        if let route { args += ["-uiRoute", route] }
        if let textSize { args += ["-dsDynamicType", textSize] }
        app.launchArguments = args
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func capture(_ name: String, pages: Int = 1, scroll: XCUIElement? = nil) {
        for page in 1...pages {
            if page > 1 { scroll?.swipeUp(velocity: .slow) }
            Thread.sleep(forTimeInterval: 0.8)
            let shot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "\(device)-\(name)-\(page)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
                let folder = URL(fileURLWithPath: dir, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(device)-\(name)-\(page).png"))
            }
        }
    }

    // MARK: Flows

    @MainActor
    func testEmptyStateAndCreateAssessment() throws {
        let app = launch(route: nil, seed: false)
        let empty = element(app, "screen.noAssessment")
        XCTAssertTrue(empty.waitForExistence(timeout: 20))
        capture("empty")

        element(app, "createFirstAssessment").tap()
        let name = element(app, "assessmentName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Annual Review")
        capture("new-assessment")
        element(app, "saveAssessment").tap()

        // The new assessment opens on its overview, with CSF 2.0 turned on.
        XCTAssertTrue(element(app, "screen.overview").waitForExistence(timeout: 10))
    }

    @MainActor
    func testRequirementListAndDetail() throws {
        let app = launch(route: "list:csf-2.0")
        let list = element(app, "screen.requirements")
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        capture("list", pages: 2, scroll: list)
        app.terminate()

        let detailApp = launch(route: "detail:csf-2.0:GV.OC-03")
        let detail = element(detailApp, "screen.requirementDetail")
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        capture("detail", pages: 4, scroll: detail)
        detailApp.terminate()

        let dark = launch(route: "detail:sp800-171r3:03.01.01", scheme: "dark")
        let detail171 = element(dark, "screen.requirementDetail")
        XCTAssertTrue(detail171.waitForExistence(timeout: 20))
        capture("detail-171-dark", pages: 3, scroll: detail171)
    }

    @MainActor
    func testSetStatusFromDetail() throws {
        let app = launch(route: "detail:csf-2.0:GV.RR-01")
        let implemented = element(app, "status.implemented")
        XCTAssertTrue(implemented.waitForExistence(timeout: 30))
        implemented.tap()
        XCTAssertTrue(implemented.isSelected, "Implemented should be selected after tapping it")

        element(app, "status.notApplicable").tap()
        let reason = element(app, "naReason")
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        // Saving without a reason must not dismiss the sheet.
        element(app, "naSave").tap()
        XCTAssertTrue(reason.exists, "The reason sheet must stay open until a reason is entered")
        reason.tap()
        reason.typeText("Roles are defined by the parent organization.")
        capture("not-applicable-reason")
        element(app, "naSave").tap()
        XCTAssertTrue(element(app, "status.notApplicable").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "status.notApplicable").isSelected, "Not applicable should be selected after saving a reason")
    }

    @MainActor
    func testQuestionnaire() throws {
        let app = launch(route: "questionnaire:csf-2.0")
        let q = element(app, "screen.questionnaire")
        XCTAssertTrue(q.waitForExistence(timeout: 20))
        capture("questionnaire")
        let next = element(app, "questionnaireNext")
        if next.waitForExistence(timeout: 5) {
            next.tap()
            capture("questionnaire-next")
        }
    }

    @MainActor
    func testExplorerPreviewAndScope() throws {
        let app = launch(route: "preview:sp800-53r5")
        let preview = element(app, "screen.frameworkPreview")
        XCTAssertTrue(preview.waitForExistence(timeout: 20))
        capture("preview-80053", pages: 3, scroll: preview)
        app.terminate()

        let explorer = launch(route: "explorer")
        XCTAssertTrue(element(explorer, "screen.explorer").waitForExistence(timeout: 20))
        capture("explorer")
        explorer.terminate()

        let scope = launch(route: "scope:sp800-53r5")
        let scopeScreen = element(scope, "screen.scope")
        XCTAssertTrue(scopeScreen.waitForExistence(timeout: 20))
        capture("scope", pages: 2, scroll: scopeScreen)
    }

    @MainActor
    func testHomeAndAccessibilitySize() throws {
        let app = launch(route: "home")
        capture("home")
        app.terminate()
        let large = launch(route: "detail:csf-2.0:GV.OC-03", textSize: "ax3")
        let detail = element(large, "screen.requirementDetail")
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        capture("detail-ax3", pages: 2, scroll: detail)
    }

    // MARK: Phase 3

    @MainActor
    func testOverviewAndNextSteps() throws {
        let app = launch(route: "overview")
        let overview = element(app, "screen.overview")
        XCTAssertTrue(overview.waitForExistence(timeout: 20))
        capture("overview", pages: 4, scroll: overview)
        app.terminate()

        let dark = launch(route: "overview", scheme: "dark")
        XCTAssertTrue(element(dark, "screen.overview").waitForExistence(timeout: 20))
        capture("overview-dark")
        dark.terminate()

        let steps = launch(route: "nextSteps")
        XCTAssertTrue(element(steps, "screen.nextSteps").waitForExistence(timeout: 20))
        capture("next-steps")
    }

    @MainActor
    func testProfileAndTiers() throws {
        let app = launch(route: "profile:csf-2.0")
        let profile = element(app, "screen.csfProfile")
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        capture("profile-summary", pages: 2, scroll: profile)
        app.buttons["Target Profile"].firstMatch.tap()
        capture("profile-target")
        app.buttons["Tiers"].firstMatch.tap()
        capture("profile-tiers", pages: 2, scroll: profile)
    }

    @MainActor
    func testRelatedRequirementsAndApply() throws {
        let app = launch(route: "detail:sp800-171r3:03.01.01")
        let detail = element(app, "screen.requirementDetail")
        XCTAssertTrue(detail.waitForExistence(timeout: 20))
        let apply = element(app, "applyToMapped")
        for _ in 0..<8 where !apply.isHittable { detail.swipeUp(velocity: .slow) }
        XCTAssertTrue(apply.exists, "Related requirements should offer to apply the answer")
        capture("related-requirements")
        apply.tap()
        XCTAssertTrue(app.navigationBars["Apply Answer"].waitForExistence(timeout: 5))
        capture("apply-to-mapped")
    }
}
