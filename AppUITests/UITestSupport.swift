import XCTest

/// Shared helpers for the UI suites. CI simulators can be slow, especially on Intel runners, so
/// waits are generous and every interaction first waits for the app to settle. CI also retries a
/// failed test (`-retry-tests-on-failure`), so one slow launch does not fail the run.
enum UITimeout {
    /// First screen after a launch: content decoding and seeding happen here.
    static let launch: TimeInterval = 120
    /// Sheets, pushed screens, and results of a tap.
    static let transition: TimeInterval = 20
    /// Work that runs in the background, such as building an export or deriving a key.
    static let work: TimeInterval = 90
}

extension XCTestCase {
    @MainActor
    var deviceName: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    /// Launches a fresh copy of the app. Launching also ends any copy still running, so tests do not
    /// call `terminate()` themselves (an explicit terminate is a common source of runner flakes).
    @MainActor
    func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Waits for a screen and then for its content to settle.
    @MainActor
    @discardableResult
    func waitForScreen(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = UITimeout.launch,
                       file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let found = element(app, id).waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "\(id) did not appear within \(Int(timeout)) seconds", file: file, line: line)
        if found { settle() }
        return found
    }

    /// Waits until an element can be tapped, not just until it exists.
    @MainActor
    @discardableResult
    func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = UITimeout.transition) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"),
                                                    object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps once the element is ready. Records a failure (instead of crashing the query) if it never is.
    @MainActor
    func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = UITimeout.transition,
                      file: StaticString = #filePath, line: UInt = #line) {
        guard waitUntilHittable(element, timeout: timeout) else {
            XCTFail("\(element) was not ready to tap within \(Int(timeout)) seconds", file: file, line: line)
            return
        }
        element.tap()
    }

    /// Scrolls until the element is on screen and tappable. Returns whether it got there.
    @MainActor
    @discardableResult
    func scroll(_ container: XCUIElement, toReveal element: XCUIElement, maxSwipes: Int = 10) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            container.swipeUp(velocity: .slow)
            settle()
        }
        return element.exists && element.isHittable
    }

    /// The scrolling list carrying a screen identifier, or the app if the screen is not a list.
    @MainActor
    func list(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        // Keep queries cheap: enumerating every collection view times out on large lists.
        let tagged = app.collectionViews.matching(identifier: id).firstMatch
        if tagged.waitForExistence(timeout: 5) && !tagged.frame.isEmpty { return tagged }
        return app
    }

    /// Gives animations and lazy rows time to finish before the next query or screenshot.
    func settle(_ seconds: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Saves one or more screenshots, scrolling between pages. Attached to the result bundle and,
    /// on CI, written to SCREENSHOT_DIR as PNGs.
    @MainActor
    func capture(_ name: String, pages: Int = 1, scroll container: XCUIElement? = nil) {
        for page in 1...pages {
            if page > 1 {
                if let container, container.exists, !container.frame.isEmpty, container.isHittable {
                    container.swipeUp(velocity: .slow)
                } else {
                    XCUIApplication().swipeUp(velocity: .slow)
                }
            }
            settle()
            save(XCUIScreen.main.screenshot(), as: "\(deviceName)-\(name)-\(page)")
        }
    }

    @MainActor
    func save(_ shot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
