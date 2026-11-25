import XCTest

/// App flows and screenshots. Uses an in-memory store with sample data (`-uiSeed sample`) and jumps
/// to screens with `-uiRoute` so captures are reliable. Each test launches the app at most a few
/// times, so a retry after a slow launch repeats little work.
final class AppFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(route: String?, seed: Bool = true, scheme: String = "light", textSize: String? = nil,
                        extra: [String] = []) -> XCUIApplication {
        var args = ["-dsColorScheme", scheme] + extra
        if seed { args += ["-uiSeed", "sample"] } else { args += ["-uiInMemory", "YES"] }
        if let route { args += ["-uiRoute", route] }
        if let textSize { args += ["-dsDynamicType", textSize] }
        return launchApp(args)
    }

    // MARK: Assessments and requirements

    @MainActor
    func testEmptyStateAndCreateAssessment() throws {
        let app = launch(route: nil, seed: false)
        waitForScreen(app, "screen.noAssessment")
        capture("empty")

        tapWhenReady(element(app, "createFirstAssessment"))
        let name = element(app, "assessmentName")
        tapWhenReady(name)
        name.typeText("Annual Review")
        capture("new-assessment")
        tapWhenReady(element(app, "saveAssessment"))

        // The new assessment opens on its overview, with CSF 2.0 turned on.
        XCTAssertTrue(element(app, "screen.overview").waitForExistence(timeout: UITimeout.transition))
    }

    @MainActor
    func testRequirementList() throws {
        let app = launch(route: "list:csf-2.0")
        waitForScreen(app, "screen.requirements")
        capture("list", pages: 2, scroll: list(app, "screen.requirements"))
    }

    @MainActor
    func testRequirementDetail() throws {
        let app = launch(route: "detail:csf-2.0:GV.OC-03")
        waitForScreen(app, "screen.requirementDetail")
        capture("detail", pages: 4, scroll: list(app, "screen.requirementDetail"))
    }

    @MainActor
    func testRequirementDetailDark() throws {
        let app = launch(route: "detail:sp800-171r3:03.01.01", scheme: "dark")
        waitForScreen(app, "screen.requirementDetail")
        capture("detail-171-dark", pages: 3, scroll: list(app, "screen.requirementDetail"))
    }

    @MainActor
    func testSetStatusFromDetail() throws {
        let app = launch(route: "detail:csf-2.0:GV.RR-01")
        waitForScreen(app, "screen.requirementDetail")
        let implemented = element(app, "status.implemented")
        tapWhenReady(implemented)
        XCTAssertTrue(implemented.isSelected, "Implemented should be selected after tapping it")

        tapWhenReady(element(app, "status.notApplicable"))
        let reason = element(app, "naReason")
        XCTAssertTrue(reason.waitForExistence(timeout: UITimeout.transition))
        // Saving without a reason must not dismiss the sheet.
        tapWhenReady(element(app, "naSave"))
        XCTAssertTrue(reason.exists, "The reason sheet must stay open until a reason is entered")
        tapWhenReady(reason)
        reason.typeText("Roles are defined by the parent organization.")
        capture("not-applicable-reason")
        tapWhenReady(element(app, "naSave"))
        let notApplicable = element(app, "status.notApplicable")
        XCTAssertTrue(notApplicable.waitForExistence(timeout: UITimeout.transition))
        XCTAssertTrue(notApplicable.isSelected, "Not applicable should be selected after saving a reason")
    }

    @MainActor
    func testQuestionnaire() throws {
        let app = launch(route: "questionnaire:csf-2.0")
        waitForScreen(app, "screen.questionnaire")
        capture("questionnaire")
        let next = element(app, "questionnaireNext")
        if waitUntilHittable(next) {
            next.tap()
            capture("questionnaire-next")
        }
    }

    // MARK: Explorer

    @MainActor
    func testFrameworkPreview() throws {
        let app = launch(route: "preview:sp800-53r5")
        // The 800-53 preview is the largest screen; give it extra time to build before scrolling.
        waitForScreen(app, "screen.frameworkPreview")
        settle(3)
        capture("preview-80053", pages: 3, scroll: list(app, "screen.frameworkPreview"))
    }

    @MainActor
    func testExplorer() throws {
        let app = launch(route: "explorer")
        waitForScreen(app, "screen.explorer")
        capture("explorer")
    }

    @MainActor
    func testScope() throws {
        let app = launch(route: "scope:sp800-53r5")
        waitForScreen(app, "screen.scope")
        settle(2)
        capture("scope", pages: 2, scroll: list(app, "screen.scope"))
    }

    @MainActor
    func testHome() throws {
        let app = launch(route: "home")
        // iPad opens on the split view, which has no single home screen.
        if deviceName == "iphone" { waitForScreen(app, "screen.home") } else { settle(5) }
        capture("home")
    }

    @MainActor
    func testAccessibilityTextSize() throws {
        let app = launch(route: "detail:csf-2.0:GV.OC-03", textSize: "ax3")
        waitForScreen(app, "screen.requirementDetail")
        capture("detail-ax3", pages: 2, scroll: list(app, "screen.requirementDetail"))
    }

    // MARK: Dashboards, profiles, mappings

    @MainActor
    func testOverview() throws {
        let app = launch(route: "overview")
        waitForScreen(app, "screen.overview")
        capture("overview", pages: 4, scroll: list(app, "screen.overview"))
    }

    @MainActor
    func testOverviewDark() throws {
        let app = launch(route: "overview", scheme: "dark")
        waitForScreen(app, "screen.overview")
        capture("overview-dark")
    }

    @MainActor
    func testNextSteps() throws {
        let app = launch(route: "nextSteps")
        waitForScreen(app, "screen.nextSteps")
        capture("next-steps")
    }

    @MainActor
    func testProfileAndTiers() throws {
        for tab in ["summary", "target", "tiers"] {
            let app = launch(route: "profile:csf-2.0", extra: ["-uiProfileTab", tab])
            waitForScreen(app, "screen.csfProfile")
            capture("profile-\(tab)", pages: 2, scroll: list(app, "screen.csfProfile"))
        }
    }

    @MainActor
    func testRelatedRequirementsAndApply() throws {
        let app = launch(route: "detail:sp800-171r3:03.01.01")
        waitForScreen(app, "screen.requirementDetail")
        let apply = element(app, "applyToMapped")
        XCTAssertTrue(scroll(list(app, "screen.requirementDetail"), toReveal: apply),
                      "Related requirements should offer to apply the answer")
        capture("related-requirements")
        apply.tap()
        XCTAssertTrue(app.navigationBars["Apply Answer"].waitForExistence(timeout: UITimeout.transition))
        capture("apply-to-mapped")
    }

    // MARK: Export, import, lock

    @MainActor
    func testExportSheet() throws {
        let app = launch(route: "export")
        waitForScreen(app, "screen.export")
        capture("export", pages: 4, scroll: list(app, "screen.export"))
    }

    @MainActor
    func testExportSpreadsheet() throws {
        let app = launch(route: "export")
        waitForScreen(app, "screen.export")
        tapWhenReady(element(app, "format.csv"))
        let scroller = list(app, "screen.export")
        let create = element(app, "export.create")
        XCTAssertTrue(scroll(scroller, toReveal: create), "The export button should be reachable")
        create.tap()
        // The finished file appears directly under the button.
        let share = element(app, "shareExport")
        var found = share.waitForExistence(timeout: UITimeout.work)
        for _ in 0..<3 where !found {
            scroller.swipeUp(velocity: .slow)
            found = share.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(found, "CSV export should produce a file to share")
        capture("export-ready")
    }

    @MainActor
    func testImportMergesTeammateFile() throws {
        let app = launch(route: "import")
        waitForScreen(app, "screen.import")
        capture("import-password")

        let password = element(app, "restorePassword")
        tapWhenReady(password)
        password.typeText("harbor-clinic\n")

        // The sample assessment is already on the device, so the import offers to merge.
        let mode = element(app, "importMode")
        XCTAssertTrue(mode.waitForExistence(timeout: UITimeout.work), "Opening the file should show its contents")
        capture("import-contents")

        tapWhenReady(element(app, "importConfirm"))
        XCTAssertTrue(element(app, "importResult").waitForExistence(timeout: UITimeout.work),
                      "The import should report what changed")
        capture("import-result")
    }

    @MainActor
    func testLockScreen() throws {
        let app = launch(route: "home", extra: ["-uiForceLock", "YES"])
        waitForScreen(app, "screen.lock")
        capture("lock")
    }
}
