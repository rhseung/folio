import FolioDomain
import FolioFixtures
import FolioStorage
import XCTest

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
        // FOLIO_GIST(`Workspace.environmentKey`)를 주면 앱이 기억한 폴더를 열지 않는다. 개발자의 Mac에서 그 폴더는 실제 GIST 폴더다. 녹음에도 따로 임시 폴더를
        // 준다(`LocalFolders.url`).
        app.launchEnvironment["FOLIO_GIST"] = gist.path(percentEncoded: false)
        // 창을 복원하면 이전 실행의 탭이 돌아오므로 끈다. 앱의 문구가 한국어이므로 언어를 한국어로 둔다.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "the window never opened")
        let stores = try GISTStore(url: gist).courseStores()
        let store = try XCTUnwrap(stores.first { $0.url.lastPathComponent.hasPrefix("EC4207") })
        let course = try store.load().model.course
        let semester = try XCTUnwrap(course.semesterId, "EC4207 has no semester")
        return (app, Targets(course: course.id, semester: semester))
    }

    // MARK: Audit

    // 바깥 링크는 새 탭에서 열린다. 검사 뒤에 탭을 닫지 않으면 탭 줄이 가득 차서, 툴바 자체의 검사 결과가 뒤의 모든 화면에 나온다.
    private func visit(_ app: XCUIApplication, _ name: String, _ link: AppLink) {
        app.open(link.url)
        audit(app, name)
        app.typeKey("w", modifierFlags: .command)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) {
        // 검사는 화면에 보이는 것을 읽으므로, 아직 들어오는 중인 페이지는 잘린 글과 곧 움직일 요소를 결과로 낸다.
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
        RunLoop.current.run(until: .now + 1)
        var found: [AuditFinding] = []
        do {
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
        element =
            issue.element.map { e in
                let label = e.label.isEmpty ? "-" : "\"\(e.label)\""
                let id = e.identifier.isEmpty ? "" : " #\(e.identifier)"
                return "\(e.elementType.name) \(label)\(id)"
            } ?? "no element"
    }

    var description: String { "\(screen): [\(type.name)] \(summary) — \(element)" }
}

// 알려진 결과는 화면, 종류, 요소로 맞추므로, 같은 화면의 새 결과는 여전히 실패한다.
enum KnownFindings {
    struct Entry {
        let screen: String
        let type: XCUIAccessibilityAuditType
        let element: String
    }

    static let entries: [Entry] = []

    static func covers(_ finding: AuditFinding) -> Bool {
        entries.contains {
            ($0.screen == "*" || $0.screen == finding.screen) && $0.type == finding.type && finding.element.contains($0.element)
        }
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
