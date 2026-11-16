// 영역 이름표의 원본이다. 학업을 다루는 모듈(domain, storage, actions, cli의 명령, 앱의 features와 platform)은
// 바로 아래 폴더를 이 이름으로 나누고, 타입과 파일 이름의 앞 낱말이 어느 영역인지 정한다.
public enum Area {
    static let table: [(name: String, fronts: [String])] = [
        ("courses", ["course", "semester", "class-time", "timetable"]),
        ("sessions", ["session", "attendance", "class", "lecture-progress", "lecture-span", "recording", "transcription"]),
        ("units", ["unit", "lecture-section", "lecture-cut", "lecture-split", "section-match"]),
        ("materials", ["material", "file", "incoming", "intake", "tex", "synctex", "pdf", "page-text"]),
        ("notes", ["note", "figure", "widget", "math", "callout", "input-guide"]),
        ("assignments", ["assignment", "due", "d-day"]),
        ("exams", ["exam", "plan-item", "plan-check", "scope"]),
        (
            "grades",
            [
                "score", "component", "policy", "gpa", "grade", "transcript", "requirement", "graduation", "handbook", "catalog",
                "category",
            ]
        ),
        ("study", ["today", "review", "quiz", "card", "problem-set", "problem", "study", "notification", "day-ribbon"]),
        ("lms", ["lms"]),
        ("claude", ["chat", "proposal"]),
        ("search", ["search"]),
        ("settings", ["settings", "setting"]),
        ("window", ["app-link", "link", "pane", "tab", "sidebar", "menu", "shortcut", "key-combo"]),
        ("folder", ["standard-layout", "term", "folder", "cleanup", "backup", "lock", "first-run", "check"]),
        ("import", ["import", "notion", "calendar", "importer", "quick-add"]),
        ("updates", ["folio-version", "patch-note", "release", "whats-new"]),
    ]

    public static var names: Set<String> { Set(table.map(\.name)) }

    // 앞 낱말이 여럿 맞으면 가장 긴 것을 고른다. `class-time`은 courses이고 `class-start`는 sessions다.
    public static func of(_ kebabName: String) -> String? {
        var best: (name: String, length: Int)?
        for (name, fronts) in table {
            for front in fronts where kebabName == front || kebabName.hasPrefix(front + "-") {
                if front.count > best?.length ?? 0 { best = (name, front.count) }
            }
        }
        return best?.name
    }
}
