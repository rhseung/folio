import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

// 기기와 시계를 고정해야 명령과 그 명령이 대신하는 액션이 바이트까지 같은 폴더를 남긴다.
struct Harness {
    static let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let device = UUID(uuidString: "D0000000-0000-4000-8000-0000000000CC")!
    let now = Date(timeIntervalSince1970: 1_793_149_200)

    static func fixtureCopy() throws -> URL {
        try Fixture.standard.copyToTemp()
    }

    static func unfile(_ course: Course, gist: URL) throws {
        let store = GISTStore(url: gist)
        var doc = try store.loadTranscript()
        doc.model.unfiledCourses.append(course)
        try store.save(doc)
    }

    struct Result {
        var code: Int32
        var out: String
        var err: String
    }

    func cli(_ args: [String], gist: URL, gradesLocked: Bool = false) -> Result {
        let lines = Lines()
        let code = CLI.$overrides.withValue(Overrides(gist: gist, device: device, now: now, gradesUnlocked: !gradesLocked)) {
            Sink.$current.withValue(Sink(out: { lines.out.append($0) }, err: { lines.err.append($0) })) {
                Folio.run(args)
            }
        }
        return Result(code: code, out: lines.out.joined(separator: "\n"), err: lines.err.joined(separator: "\n"))
    }

    func direct(_ action: some Action, gist: URL) throws {
        try action.run(ActionContext(gist: GISTStore(url: gist), device: device, now: now))
    }

    func expectSame(
        _ args: [String], setup: [[String]] = [], prepare: (URL) throws -> Void = { _ in },
        _ action: (GISTStore) throws -> any Action, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let (a, b) = (try Self.fixtureCopy(), try Self.fixtureCopy())
        try prepare(a)
        try prepare(b)
        for line in setup {
            for gist in [a, b] {
                let r = cli(line, gist: gist)
                #expect(r.code == 0, "setup \(line): \(r.err)", sourceLocation: sourceLocation)
            }
        }
        let r = cli(args, gist: a)
        #expect(r.code == 0, "\(args): \(r.err)", sourceLocation: sourceLocation)
        try direct(try action(GISTStore(url: b)), gist: b)
        let (fa, fb) = (try Self.files(a), try Self.files(b))
        #expect(fa.keys.sorted() == fb.keys.sorted(), "files differ for \(args)", sourceLocation: sourceLocation)
        for (path, data) in fa where Self.canonical(fb[path]) != Self.canonical(data) {
            Issue.record("\(path) differs for \(args)", sourceLocation: sourceLocation)
        }
    }

    // 액션이 안에서 만드는 ID(출결 행, 새로 추적한 파일)는 실행마다 무작위이므로, UUID를 처음 나온 순서로 다시 번호 매긴다. 같은 ID는 여전히 같은 자리에 나와야 한다.
    static func canonical(_ data: Data?) -> String? {
        guard let data else { return nil }

        // 자료의 bookmark는 사본의 절대 경로를 담으므로, 두 사본 사이에서 항상 다르다.
        let text = String(decoding: data, as: UTF8.self).replacing(/"bookmark" : "[^"]*"/, with: #""bookmark" : """#)
        var seen: [Substring: Int] = [:]
        return text.replacing(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/) { m in
            let key = m.output.uppercased()[...]
            if seen[key] == nil { seen[key] = seen.count }
            return "<id\(seen[key]!)>"
        }
    }

    static func files(_ root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let root = root.resolvingSymlinksInPath()
        let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = e?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            out[String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
        return out
    }

    func file(_ gist: GISTStore, _ course: UUID = graphTheory) throws -> CourseFile {
        try ActionContext(gist: gist, device: device).file(course)
    }
}

private final class Lines: @unchecked Sendable {
    var out: [String] = []
    var err: [String] = []
}
