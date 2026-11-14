import FolioDomain
import FolioStorage
import Foundation

@Action(
    "import notes", "노션 강의 정리와 점수를 노트, 회차, 성적 항목으로",
    discussion: """
        덤프 폴더는 과목마다 <노션 페이지 ID>/index.json, notes/, assets/를 가진다. 노트 ID가 노션 페이지 ID라서 다시
        실행해도 중복되지 않고, 기존 항목에는 덧붙이기만 한다.
        """,
    effect: .creates, done: "노션 강의 정리를 가져왔습니다", examples: ["folio import notes ~/Downloads/notion-dump --dry-run"],
    phrases: ["노션 강의 정리 가져오기"])
public struct ImportNotes {
    /// 덤프 폴더
    @Arg @Folder var folder: String

    public func run(_ ctx: ActionContext) throws {
        let root = URL(filePath: folder, directoryHint: .isDirectory)
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "index.json").path) }
            .sorted { $0.path < $1.path }
        let dumps = try folders.map {
            ($0, try JSONDecoder().decode(NotionCourseDump.self, from: Data(contentsOf: $0.appending(path: "index.json"))))
        }
        var links: [String: String] = [:]
        for (_, dump) in dumps {
            for n in dump.notes { links[n.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")] = n.title }
        }

        for (dumpFolder, dump) in dumps {
            guard ctx.hasFolder(dump.coursePageId) else {
                if !dump.notes.isEmpty || !dump.scores.isEmpty {
                    ctx.note(String(localized: .noteImportNotesNoFolder(dump.title, dump.notes.count, dump.scores.count)))
                }
                continue
            }
            let store = try ctx.store(dump.coursePageId)
            // 파일이 아니라 항목으로 센다. Folio 밖에서 파일을 지우거나 이름을 바꾼 항목도 id와 경로를 갖고 있어서, 그 노트를
            // 다시 계획하면 둘을 모두 가진 둘째 항목이 생긴다.
            let existing = Set(try ctx.file(dump.coursePageId).notes.map(\.id))
            let r = NotionNotesImporter.merge(
                dump, into: try ctx.file(dump.coursePageId), existingNotes: existing, calendar: ctx.calendar, device: ctx.device,
                now: ctx.now)
            ctx.note(
                String(
                    localized: .noteImportNotesCourse(
                        dump.title, r.sessionsAdded, r.notes.count, r.componentsAdded, r.scoresAdded,
                        dump.images.filter { $0.file != nil }.count)))
            for w in r.warnings { ctx.note(String(localized: .noteImportNotesCheck(dump.title, w))) }

            var urls: [UUID: URL] = [:]
            for plan in r.notes where !existing.contains(plan.id) {
                let url = store.newNoteURL(
                    title: plan.title, format: .markdown, avoiding: Set(urls.values.map { $0.deletingPathExtension().lastPathComponent }))
                urls[plan.id] = url
                ctx.record(Change(.added, ctx.relative(url)))
            }

            if !ctx.dryRun { try store.writeNotionNotes(r.notes, dump: dump, folder: dumpFolder, links: links, at: urls) }
            let paths = urls.mapValues { store.notePath(of: $0) }
            try ctx.edit(dump.coursePageId) { f in
                f = r.file
                for plan in r.notes {
                    if let path = paths[plan.id] {
                        f.notes.append(NoteEntry(id: plan.id, device: ctx.device, at: ctx.now, path: path, meta: plan.meta))
                    }
                }
            }
        }
    }
}
