import FolioDomain
import FolioFixtures
import FolioStorage
import XCTest

/// Every main screen through `performAccessibilityAudit()` (#471). Each test launches the app on a fresh `busyDay`
/// fixture in a temporary folder, opens screens by their `folio://` links and audits each one.
///
/// UI tests take the screen and the keyboard, and the app they launch shares its defaults with the installed Folio,
/// so they run in CI (`mise run test-a11y`), not on a Mac someone is using.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    func testPlaces() throws {
        let (app, targets) = try launch()
        audit(app, "today")
        for (name, link) in [
            ("semester", AppLink(.semester, targets.semester)),
            ("grades", .place(.grades)),
            ("requirements", .place(.requirements)),
            ("people", .place(.people)),
            ("codes", .place(.codes)),
        ] {
            visit(app, name, link)
        }
    }

    func testCoursePages() throws {
        let (app, targets) = try launch()
        visit(app, "course", .course(targets.course))
        for page in AppLink.CoursePage.allCases where page != .overview {
            visit(app, "course-\(page.rawValue)", .course(targets.course, page: page))
        }
    }

    func testSettings() throws {
        let (app, _) = try launch()
        for page in AppLink.SettingsPage.allCases {
            visit(app, "settings-\(page.rawValue)", .settings(page))
        }
    }

    func testSearch() throws {
        let (app, _) = try launch()
        app.typeKey("k", modifierFlags: .command)
        app.typeText("EC4207")
        audit(app, "search")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: Launch

    private struct Targets {
        let course: UUID
        let semester: UUID
    }

    private func launch() throws -> (XCUIApplication, Targets) {
        continueAfterFailure = true
        let gist = try Scenario.busyDay.copyToTemp()
        let folder = gist.deletingLastPathComponent()
        let app = XCUIApplication()
        addTeardownBlock { @MainActor in
            app.terminate()
            try? FileManager.default.removeItem(at: folder)
        }
        // FOLIO_GIST (Workspace.environmentKey) keeps the app off the folder it remembers, which on a developer's Mac
        // is the real GIST folder, and gives its recordings a temporary folder of their own (LocalFolders.url).
        app.launchEnvironment["FOLIO_GIST"] = gist.path(percentEncoded: false)
        // Restored windows would bring back tabs from an earlier run; Korean is the language the app is written in.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "the window never opened")
        // The course busyDay fills most: units, a split lecture PDF, sessions, exams.
        let stores = try GISTStore(url: gist).courseStores()
        let store = try XCTUnwrap(stores.first { $0.url.lastPathComponent.hasPrefix("EC4207") })
        let course = try store.load().model.course
        return (app, Targets(course: course.id, semester: course.semesterId))
    }

    // MARK: Audit

    /// A link from outside opens in a new tab; closing it after the audit keeps the tab row from filling up, which
    /// would put the toolbar's own findings on every later screen.
    private func visit(_ app: XCUIApplication, _ name: String, _ link: AppLink) {
        app.open(link.url)
        audit(app, name)
        app.typeKey("w", modifierFlags: .command)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        // The audit reads what is on screen: a page that is still animating in reports clipped text and elements
        // that are about to move.
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        RunLoop.current.run(until: .now + 1)
        var found: [AuditFinding] = []
        do {
            // Every issue is collected so one run lists them all; the ones not known below fail the test.
            try app.performAccessibilityAudit(for: .all) { issue in
                found.append(AuditFinding(screen: screen, issue: issue))
                return true
            }
        } catch {
            XCTFail("\(screen): the audit did not run: \(error)")
        }
        for finding in found where !KnownFindings.covers(finding) {
            XCTFail(finding.description)
        }
    }
}

struct AuditFinding: CustomStringConvertible {
    let screen: String
    let type: XCUIAccessibilityAuditType
    let summary: String
    let element: String

    @MainActor
    init(screen: String, issue: XCUIAccessibilityAuditIssue) {
        self.screen = screen
        type = issue.auditType
        summary = issue.compactDescription
        element = issue.element.map { e in
            let label = e.label.isEmpty ? "-" : "\"\(e.label)\""
            let id = e.identifier.isEmpty ? "" : " #\(e.identifier)"
            return "\(e.elementType.name) \(label)\(id)"
        } ?? "no element"
    }

    var description: String { "\(screen): [\(type.name)] \(summary) — \(element)" }
}

/// Findings left for later, each one a line of #471's checklist. Matched by screen, type and element, so a new finding
/// on the same screen still fails.
enum KnownFindings {
    struct Entry {
        let screen: String
        let type: XCUIAccessibilityAuditType
        let element: String
    }

    static let entries: [Entry] = []

    static func covers(_ finding: AuditFinding) -> Bool {
        entries.contains { ($0.screen == "*" || $0.screen == finding.screen) && $0.type == finding.type && finding.element.contains($0.element) }
    }
}

extension XCUIAccessibilityAuditType {
    var name: String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element"), (.hitRegion, "hit-region"),
            (.sufficientElementDescription, "description"), (.action, "action"), (.parentChild, "parent-child"),
        ]
        return names.first { contains($0.0) }?.1 ?? "type \(rawValue)"
    }
}

extension XCUIElement.ElementType {
    var name: String {
        switch self {
        case .button: "button"
        case .staticText: "text"
        case .image: "image"
        case .textField: "text-field"
        case .searchField: "search-field"
        case .group: "group"
        case .cell: "cell"
        case .link: "link"
        case .menuButton: "menu-button"
        case .popUpButton: "pop-up"
        case .checkBox: "check-box"
        case .toggle: "toggle"
        case .slider: "slider"
        case .scrollView: "scroll-view"
        case .outline: "outline"
        case .outlineRow: "outline-row"
        case .toolbar: "toolbar"
        case .tabGroup: "tab-group"
        case .radioButton: "radio"
        case .segmentedControl: "segmented"
        default: "element \(rawValue)"
        }
    }
}
