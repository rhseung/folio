import FolioDomain
import FolioStorage
import Foundation

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
