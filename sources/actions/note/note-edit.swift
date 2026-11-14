import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// 각 `old`는 앞선 바꾸기가 남긴 글에서 정확히 한 번 나와야 한다. 그래서 `expected`의 역할도 한다. 다른 곳에서 바뀐
// 글은 더는 맞지 않는다.
@Action(
    "note edit", "노트 일부 고치기. 찾아 바꾸거나 끝에 붙인다. 노트 전체를 다시 쓰지 않는다", done: "노트 '{note}'을(를) 고쳤습니다",
    examples: [
        #"folio note edit EC4207/09-08 --old "non-adjacent" --new "서로 이웃하지 않는""#,
        #"folio note edit EC4207/09-08 --append "질문: 최대 매칭은 어떻게 찾나""#,
    ],
    phrases: ["노트 일부 수정", "노트에 덧붙이기", "노트 끝에 추가", "노트 찾아 바꾸기"], cli: .manual(reason: "--old와 --new를 준 순서대로 짝지어 바꿀 목록을 만든다"))
public struct NoteEdit {
    public struct Replacement: Codable, Sendable, Equatable {
        public var old: String
        public var new: String
        public init(old: String, new: String) {
            self.old = old
            self.new = new
        }
    }
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path
    /// 찾아 바꿀 원문(old)과 새 글(new). old는 노트에 꼭 한 번 나와야 하고, 준 순서대로 바꾼다
    var replacements: [Replacement] = []
    /// 노트 끝에 붙일 글. 새 줄에서 시작한다. 빈 줄을 두려면 앞에 줄바꿈을 넣는다
    var append: String?

    public func run(_ ctx: ActionContext) throws {
        guard !replacements.isEmpty || append?.isEmpty == false else { throw ActionError.rule(String(localized: .errorNoteEditNothing)) }
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        let text = try Self.edited(try store.read(file), replacements, append: append, note: note)
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }

    static func edited(_ text: String, _ replacements: [Replacement], append: String?, note: String) throws -> String {
        var text = text
        for (i, r) in replacements.enumerated() {
            let n = i + 1
            guard !r.old.isEmpty else { throw ActionError.rule(String(localized: .errorNoteEditEmptyOld(n))) }
            let ranges = text.ranges(of: r.old)
            guard let range = ranges.first else {
                throw ActionError.conflict(String(localized: .errorNoteEditMissing(n, Self.excerpt(r.old), note)))
            }
            guard ranges.count == 1 else {
                throw ActionError.rule(String(localized: .errorNoteEditAmbiguous(n, Self.excerpt(r.old), ranges.count)))
            }
            text.replaceSubrange(range, with: r.new)
        }
        if let append, !append.isEmpty {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += append.hasSuffix("\n") ? append : append + "\n"
        }
        return text
    }

    static func excerpt(_ s: String) -> String {
        let line = s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? s
        return line.count > 40 ? line.prefix(40) + "…" : line
    }
}
