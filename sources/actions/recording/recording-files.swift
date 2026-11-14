import FolioDomain
import FolioStorage
import Foundation

enum RecordingFiles {
    static func follow(_ moves: [PlannedMove], _ ctx: ActionContext) throws {
        for store in try ctx.gist.courseStores() {
            let prefix = ctx.relative(store.url) + "/"
            let byPath = Dictionary(
                moves.filter { $0.from.hasPrefix(prefix) && $0.to.hasPrefix(prefix) }
                    .map { (String($0.from.dropFirst(prefix.count)), String($0.to.dropFirst(prefix.count))) },
                uniquingKeysWith: { a, _ in a })
            guard !byPath.isEmpty else { continue }
            let course = try store.load().model.course.id
            try ctx.edit(course) { f in
                for i in f.recordings.indices {
                    let r = f.recordings[i]
                    let file =
                        byPath[r.file]
                        ?? byPath[r.transcriptFile].flatMap { to in
                            to.hasSuffix(Recording.transcriptSuffix)
                                ? String(to.dropLast(Recording.transcriptSuffix.count)) + "." + (r.file as NSString).pathExtension : nil
                        }
                    guard let file, file != r.file else { continue }
                    f.recordings[i].file = file
                    f.recordings[i].touch(by: ctx.device, at: ctx.now)
                }
            }
        }
    }
}
