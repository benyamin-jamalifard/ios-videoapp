import XCTest

/// Taps through the app against the live site, in both modes: a film must
/// open (and stay open) from home, every kind of list and search.
/// CI passes `TEST_RUNNER_KF_SHOTS=<dir>`; each step saves a screenshot there.
final class NavigationUITests: XCTestCase {
    /// Persian texts seen on English-mode screens; reported once per test.
    private var persianSeen: [String] = []

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCTAssertTrue(persianSeen.isEmpty, "Persian in the English app: " + persianSeen.joined(separator: " | "))
        persianSeen = []
    }

    func testIranHomeOpensFilm() { homeOpensFilm(mode: "ir") }
    func testAbroadHomeOpensFilm() { homeOpensFilm(mode: "intl") }
    func testIranCategoryOpensFilm() { categoryOpensFilm(mode: "ir") }
    func testAbroadCategoryOpensFilm() { categoryOpensFilm(mode: "intl") }
    func testIranSearchOpensFilm() { searchOpensFilm(mode: "ir") }
    func testAbroadSearchOpensFilm() { searchOpensFilm(mode: "intl") }
    func testIranExploreShortcutsOpen() { shortcutsOpen(mode: "ir") }
    func testAbroadExploreShortcutsOpen() { shortcutsOpen(mode: "intl") }

    func testEveryTabOpens() {
        for mode in ["ir", "intl"] {
            for tab in ["home", "explore", "search", "downloads", "profile"] {
                let app = launch(mode, "kelaketfilm://app/tab/\(tab)")
                sleep(4)
                XCTAssertEqual(app.state, .runningForeground, "\(mode) \(tab) crashed")
                save("\(mode)-tab-\(tab)")
                // Nothing tells foreign users that playback is limited.
                let notice = NSPredicate(format: "label CONTAINS[c] 'available in' OR label CONTAINS[c] 'only in iran' OR label CONTAINS 'فقط در ایران'")
                XCTAssertFalse(app.staticTexts.matching(notice).firstMatch.exists, "\(mode) \(tab) shows a region notice")
            }
        }
    }

    // MARK: Flows

    private func homeOpensFilm(mode: String) {
        let app = launch(mode, "")
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 45), "home has no posters")
        app.swipeUp()
        openPoster(in: app, step: "\(mode)-home")
    }

    private func categoryOpensFilm(mode: String) {
        let app = launch(mode, "kelaketfilm://app/tab/explore")
        let genre = app.buttons.matching(identifier: "genre").firstMatch
        XCTAssertTrue(genre.waitForExistence(timeout: 45), "no categories")
        save("\(mode)-explore")
        genre.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 45), "category is empty")
        sleep(2)
        save("\(mode)-category")
        openPoster(in: app, step: "\(mode)-category")
        // Back on the category, a second film opens too (the old bug popped back here).
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 20))
        openPoster(in: app, step: "\(mode)-category-again", index: 1)
    }

    private func searchOpensFilm(mode: String) {
        let app = launch(mode, "kelaketfilm://app/tab/search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText("joker")
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 45), "no search results")
        sleep(2)
        save("\(mode)-search")
        openPoster(in: app, step: "\(mode)-search")
    }

    private func shortcutsOpen(mode: String) {
        let names = mode == "ir"
            ? ["آرشیو", "۲۵۰ برتر IMDb", "کالکشن‌ها"]
            : ["All titles", "IMDb Top 250", "Collections"]
        for name in names {
            let app = launch(mode, "kelaketfilm://app/tab/explore")
            let shortcut = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(shortcut.waitForExistence(timeout: 45), "no \(name) shortcut")
            reveal(shortcut, in: app)
            shortcut.tap()
            sleep(8)
            save("\(mode)-shortcut-\(names.firstIndex(of: name)!)")
            XCTAssertEqual(app.state, .runningForeground)
            // Lists of films open a film page.
            if name != names[2], app.buttons.matching(identifier: "poster").firstMatch.exists {
                openPoster(in: app, step: "\(mode)-shortcut-\(names.firstIndex(of: name)!)")
            }
        }
    }

    // MARK: Helpers

    private func launch(_ mode: String, _ link: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-kf.region.override", mode, "-kf.open", link]
        app.launch()
        return app
    }

    /// Taps a visible poster and checks the film page opens and stays open.
    private func openPoster(in app: XCUIApplication, step: String, index: Int = 0) {
        let visible = app.buttons.matching(identifier: "poster").allElementsBoundByIndex.filter { onScreen($0, in: app) }
        XCTAssertFalse(visible.isEmpty, "\(step): no visible poster")
        visible[min(index, visible.count - 1)].tap()
        let page = app.descendants(matching: .any).matching(identifier: "film-detail").firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 45), "\(step): the film page did not open")
        sleep(3)
        XCTAssertTrue(page.exists, "\(step): the film page closed by itself")
        save("\(step)-film")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    /// `isHittable` fails outright for cells a lazy row has not laid out, so
    /// the frame is checked instead (clear of the navigation and tab bars).
    private func onScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty, frame.width > 20 else { return false }
        let safe = app.frame.insetBy(dx: 0, dy: 100)
        return safe.contains(CGPoint(x: frame.midX, y: frame.midY)) && frame.minX >= 0 && frame.maxX <= app.frame.maxX
    }

    /// Scrolls a horizontal row until `element` is on screen.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for direction in [-1.0, 1.0] {
            for _ in 0..<4 where !onScreen(element, in: app) {
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = origin.withOffset(CGVector(dx: app.frame.midX, dy: element.frame.midY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 220 * direction, dy: 0)))
            }
        }
    }

    /// The English app must not show a single Persian letter.
    private func checkEnglish(_ app: XCUIApplication, _ step: String) {
        guard step.hasPrefix("intl") else { return }
        let persian = NSPredicate(format: "label MATCHES %@", #"(?s).*[\u0600-\u06FF].*"#)
        let labels = app.descendants(matching: .any).matching(persian).allElementsBoundByIndex.map(\.label)
        for label in Set(labels) where !persianSeen.contains(where: { $0.hasSuffix(String(label.prefix(80))) }) {
            persianSeen.append("\(step): \(label.prefix(80))")
        }
    }

    /// Saves a screenshot for the CI log, and checks English screens for Persian.
    private func save(_ name: String) {
        checkEnglish(XCUIApplication(), name)
        guard let dir = ProcessInfo.processInfo.environment["KF_SHOTS"] else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ui-\(name).png"))
    }
}
