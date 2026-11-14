import FolioDomain
import FolioStorage
import Foundation

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
