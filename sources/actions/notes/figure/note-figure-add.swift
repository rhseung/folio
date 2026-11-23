import FolioDomain
import FolioStorage
import Foundation

@Action(
    "note figure add", "노트 그림(SVG)을 Notes/assets에 새로 쓰기. 같은 이름이 있으면 쓰지 않는다. 노트에는 ![설명](assets/<이름>.svg)로 넣는다",
    discussion: "쓸 때 그림 스타일(다크 포함)과 화살촉을 넣고 $…$를 LaTeX 글자로 바꾼 뒤, 스크립트, 바깥 참조, 칠한 색, 긴 글, 큰 촉, 라벨 겹침을 본다. 형식은 folio note format.",
    effect: .creates, done: "그림 '{name}'을(를) 만들었습니다",
    phrases: ["그림 추가", "SVG 그림 넣기", "노트 그림 만들기", "도식 그리기", "다이어그램 그림"], panel: true)
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
        let finished = try Self.finish(svg, korean: Self.korean(ctx, course))
        guard !FileManager.default.fileExists(atPath: store.fileURL(path).path) else {
            throw ActionError.conflict(String(localized: .errorFigureTaken(path)))
        }
        try ctx.io(Change(.added, try ctx.relative(course, path))) { try store.createText(path, text: finished) }
    }

    static func fileName(_ name: String) throws -> String {
        guard let file = NoteFigure.fileName(name) else { throw ActionError.rule(String(localized: .errorFigureName(name))) }
        return file
    }

    static func korean(_ ctx: ActionContext, _ course: Course.ID) throws -> Bool {
        FigureStyle.allowsKorean(try ctx.file(course).course, catalog: try ctx.catalog())
    }

    static func finish(_ svg: String, korean: Bool) throws -> String {
        let finished = try NoteFigureFinish.finish(svg, korean: korean)
        guard finished.problems.isEmpty else { throw ActionError.rule(finished.problems.map(\.message).joined(separator: "\n")) }
        return finished.svg
    }
}
