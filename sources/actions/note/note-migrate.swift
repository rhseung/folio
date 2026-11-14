import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// 파일을 건드리기 전에 항목을 저장하므로, 중간에 멈춘 실행은 다시 돌리면 마무리된다. 없어진 회차, 단원, 시험으로
// 가는 링크와 한 회차에 같은 종류로 붙은 둘째 노트는 버린다. 둘 중 하나라도 있으면 모델이 파일 전체를 거절한다.
@Action(
    "note migrate", "노트 frontmatter의 프로퍼티를 course.json으로 옮기고 파일에서 지우기. 예전 노트를 한 번 정리한다",
    discussion:
        "Folio가 쓴 키(id, kind, sessionId, unitIds, examId, tags, math)만 옮기고, 다른 키는 파일에 남긴다. course.json에 이미 항목이 있는 노트는 태그를 합치고 나머지는 항목에서 빈 값만 채우며, ID는 항목의 것을 둔다. 실제 폴더에서는 백업한 뒤 --dry-run으로 먼저 본다.",
    done: "노트 프로퍼티를 course.json으로 옮겼습니다", examples: ["folio note migrate --dry-run", "folio note migrate EC4207"],
    phrases: ["노트 프로퍼티 옮기기", "frontmatter 정리"])
public struct NoteMigrate {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        for course in courses {
            let store = try ctx.store(course)
            let notes = try store.frontmatterNotes()
            guard !notes.isEmpty else { continue }
            try reportOldIDs(notes, course: course, store: store, ctx)
            try ctx.edit(course) { f in
                for n in notes {
                    if let i = f.notes.firstIndex(where: { $0.path == store.notePath(of: n.url) }) {
                        Self.merge(n.meta, into: i, of: &f, ctx)
                        continue
                    }
                    var meta = n.meta
                    meta.sessionId = meta.sessionId.flatMap { id in f.sessions.contains { $0.id == id } ? id : nil }
                    meta.examId = meta.examId.flatMap { id in f.exams.contains { $0.id == id } ? id : nil }
                    meta.unitIds = meta.unitIds.filter { id in f.units.contains { $0.id == id } }
                    // Finder에서 복사한 노트는 원본의 id를 지니므로 사본에 새 id를 준다.
                    let id = meta.id.flatMap { id in f.notes.contains { $0.id == id } ? nil : id } ?? UUID()
                    if meta.kind == .rough || meta.kind == .review, let s = f.sessions.first(where: { $0.id == meta.sessionId }) {
                        let pointed = s.note(of: meta.kind)
                        if pointed.map({ $0 != id }) ?? false { meta.sessionId = nil } else { f.linkNote(id, to: s.id, as: meta.kind) }
                    }
                    f.notes.append(NoteEntry(id: id, device: ctx.device, at: ctx.now, path: store.notePath(of: n.url), meta: meta))
                }
            }

            for n in notes {
                try ctx.io(Change(.changed, ctx.relative(n.url))) {
                    try store.write(NoteFile(url: n.url, meta: NoteMeta(id: nil)), text: n.text)
                }
            }
        }
    }

    static func merge(_ meta: NoteMeta, into i: Int, of f: inout CourseFile, _ ctx: ActionContext) {
        let before = f.notes[i]
        var e = before
        for tag in meta.tags where !e.tags.contains(tag) { e.tags.append(tag) }
        if e.kind == .examSummary, e.examId == nil, let exam = meta.examId, f.exams.contains(where: { $0.id == exam }) { e.examId = exam }
        if e.kind == .unit, e.unitIds.isEmpty { e.unitIds = meta.unitIds.filter { id in f.units.contains { $0.id == id } } }
        if e != before {
            e.touch(by: ctx.device, at: ctx.now)
            f.notes[i] = e
        }
        if e.kind == .rough || e.kind == .review, f.sessions(pointingAt: e.id).isEmpty,
            let s = f.sessions.first(where: { $0.id == meta.sessionId }), s.note(of: e.kind) == nil
        {
            f.linkNote(e.id, to: s.id, as: e.kind)
        }
    }

    // 회차와 ID 링크가 이미 항목의 id를 가리키므로 그 id를 지킨다. frontmatter의 다른 id로 가는 링크는 깨지므로 사람이
    // 고치도록 이름을 알리고, 아무것도 가리키지 않는 id는 조용히 버린다.
    func reportOldIDs(_ notes: [FrontmatterNote], course: UUID, store: CourseStore, _ ctx: ActionContext) throws {
        let file = try ctx.file(course)
        let replaced = notes.compactMap { n -> (path: String, id: UUID)? in
            let path = store.notePath(of: n.url)
            guard let old = n.meta.id, let entry = file.notes.first(where: { $0.path == path }), entry.id != old,
                !file.notes.contains(where: { $0.id == old })
            else { return nil }
            return (path, old)
        }
        guard !replaced.isEmpty else { return }
        let stripped = Dictionary(notes.map { ($0.url.standardizedFileURL, $0.text) }, uniquingKeysWith: { a, _ in a })
        let texts = try ctx.notes(course).map { n in try stripped[n.url.standardizedFileURL] ?? store.read(n) }
        for r in replaced {
            let key = r.id.uuidString.lowercased()
            let places =
                file.sessions.count { $0.roughNoteId == r.id || $0.reviewNoteId == r.id }
                + texts.count { $0.lowercased().contains(key) }
            if places > 0 { ctx.note(String(localized: .noteMigrateOldId(r.path, r.id.uuidString, places))) }
        }
    }
}
