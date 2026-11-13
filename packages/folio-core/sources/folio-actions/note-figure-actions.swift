import FolioDomain
import FolioStorage
import Foundation

// Pictures and widgets come from Claude as text and are proposals until the user applies them (#441, #92), so each
// write is checked before it lands: what fails here would otherwise show up only as a broken drawing in the note.
// No examples: the equivalence test runs each one for real, and these read their text from a file.

@Action(
    "note figure add", "노트 그림(SVG)을 Notes/assets에 새로 쓰기. 같은 이름이 있으면 쓰지 않는다. 노트에는 ![설명](assets/<이름>.svg)로 넣는다",
    discussion: "XML이 올바른지, 스크립트와 바깥 참조가 없는지, 다크 모드 규칙(prefers-color-scheme: dark)이 있는지 본다. 노트 형식은 folio note format.",
    effect: .creates, done: "그림 '{name}'을(를) 만들었습니다",
    phrases: ["그림 추가", "SVG 그림 넣기", "노트 그림 만들기", "도식 그리기", "다이어그램 그림"])
public struct NoteFigureAdd {
    /// 과목
    @Arg var course: Course.ID
    /// Notes/assets 안의 파일 이름. 확장자를 빼면 .svg를 붙인다
    @Arg var name: String
    /// SVG 원문
    @FromFile("figure.svg") var svg: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteFigure.path(try Self.fileName(name))
        try Self.check(svg)
        // Another note may already show the picture under that name; a new one goes under a name of its own.
        guard !FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.conflict(String(localized: .errorFigureTaken(path)))
        }
        try ctx.io(Change(.added, try ctx.relative(course, path))) { try store.createText(path, text: svg) }
    }

    static func fileName(_ name: String) throws -> String {
        guard let file = NoteFigure.fileName(name) else { throw ActionError.rule(String(localized: .errorFigureName(name))) }
        return file
    }

    static func check(_ svg: String) throws {
        let problems = NoteFigure.problems(svg)
        guard problems.isEmpty else { throw ActionError.rule(problems.map(\.message).joined(separator: "\n")) }
    }
}

/// Replaces the whole file against the hash of what was read, as `note write` does: a picture changed meanwhile by
/// the app or another device is not overwritten.
@Action(
    "note figure write", "노트 그림(SVG) 전체를 바꾸기. note figure show의 해시를 --expect로 넘겨 그사이 바뀌지 않았는지 확인한다",
    done: "그림 '{name}'을(를) 썼습니다", phrases: ["그림 다시 그리기", "SVG 수정"])
public struct NoteFigureWrite {
    /// 과목
    @Arg var course: Course.ID
    /// Notes/assets 안의 그림 이름
    @Arg var name: String
    /// 새 SVG 원문
    @FromFile("figure.svg") var svg: String
    /// note figure show가 알려 준 해시. 그림이 그사이 바뀌었으면 쓰지 않는다
    var expect: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteFigure.path(try NoteFigureAdd.fileName(name))
        try NoteFigureAdd.check(svg)
        try Self.match(store, path, expect)
        try ctx.io(Change(.changed, try ctx.relative(course, path))) { try store.writeText(path, text: svg) }
    }

    static func match(_ store: CourseStore, _ path: String, _ expect: String) throws {
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.notFound(String(localized: .errorFigureMissing(path)))
        }
        guard ContentHash.of(try MaterialWrite.read(store, path)) == expect.trimmingCharacters(in: .whitespaces).lowercased() else {
            throw ActionError.conflict(String(localized: .errorFigureChanged(path)))
        }
    }
}

@Action(
    "note widget add", "노트 위젯 HTML을 .folio/widgets에 새로 쓰기. 노트에는 cb-widget 블록 {\"id\": \"<ID>\", \"height\": 320}으로 넣는다",
    discussion: "바깥 파일과 주소를 불러오는 부분이 있으면 쓰지 않는다. 위젯 환경은 folio note format.",
    effect: .creates, done: "위젯 {id}을(를) 만들었습니다",
    phrases: ["위젯 만들기", "인터랙티브 위젯", "cb-widget 추가", "위젯 HTML"])
public struct NoteWidgetAdd {
    /// 과목
    @Arg var course: Course.ID
    @New var id: NoteWidget.ID
    /// 위젯 HTML 페이지
    @FromFile("widget.html") var html: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteWidget.path(id)
        try Self.check(html)
        guard !FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.conflict(String(localized: .errorWidgetTaken(id.uuidString)))
        }
        try ctx.io(Change(.added, try ctx.relative(course, path))) { try store.createText(path, text: html) }
        ctx.made(id)
    }

    static func check(_ html: String) throws {
        let problems = NoteWidget.problems(html)
        guard problems.isEmpty else { throw ActionError.rule(problems.map(\.message).joined(separator: "\n")) }
    }
}

@Action(
    "note widget write", "노트 위젯 HTML 전체를 바꾸기. note widget show의 해시를 --expect로 넘겨 그사이 바뀌지 않았는지 확인한다",
    done: "위젯 {widget}을(를) 썼습니다", phrases: ["위젯 다시 쓰기", "위젯 수정"])
public struct NoteWidgetWrite {
    /// 과목
    @Arg var course: Course.ID
    /// 위젯 ID
    @Arg var widget: NoteWidget.ID
    /// 새 위젯 HTML
    @FromFile("widget.html") var html: String
    /// note widget show가 알려 준 해시. 위젯이 그사이 바뀌었으면 쓰지 않는다
    var expect: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let path = NoteWidget.path(widget)
        try NoteWidgetAdd.check(html)
        guard FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.notFound(String(localized: .errorWidgetMissing(widget.uuidString)))
        }
        guard ContentHash.of(try MaterialWrite.read(store, path)) == expect.trimmingCharacters(in: .whitespaces).lowercased() else {
            throw ActionError.conflict(String(localized: .errorWidgetChanged(widget.uuidString)))
        }
        try ctx.io(Change(.changed, try ctx.relative(course, path))) { try store.writeText(path, text: html) }
    }
}
