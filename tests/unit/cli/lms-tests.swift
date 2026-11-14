import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

struct LMSTests {
    let h = Harness()
    let course = Harness.graphTheory

    @Test func seen() throws {
        try h.expectSame(["lms", "seen", "27967", "28011", "--items", "file:139109", "--items", "notice:23464"]) { _ in
            LMSSeen(classrooms: [27967, 28011], items: ["file:139109", "notice:23464"])
        }
    }

    @Test func mark() throws {
        try h.expectSame(["lms", "mark", "notice:23464", "file:139109"]) { _ in
            LMSMark(keys: ["notice:23464", "file:139109"], handled: true)
        }
    }

    @Test func seenAndMarkWriteSettings() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["lms", "seen", "28011", "27967", "--items", "file:2", "--items", "file:1"], gist: gist).code == 0)
        #expect(h.cli(["lms", "seen", "27967"], gist: gist).code == 0)
        var lms = try GISTStore(url: gist).loadSettings().model.lms
        #expect(lms.known == [27967, 28011])
        #expect(lms.handled == [LMSKey(kind: .file, id: 1), LMSKey(kind: .file, id: 2)])

        #expect(h.cli(["lms", "mark", "file:1", "--off"], gist: gist).code == 0)
        lms = try GISTStore(url: gist).loadSettings().model.lms
        #expect(lms.handled == [LMSKey(kind: .file, id: 2)])
    }

    @Test func refusesBadInput() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["lms", "seen", "27967", "--items", "file"], gist: gist).code != 0)
        #expect(h.cli(["lms", "mark", "file"], gist: gist).code != 0)
    }

    @Test func assignmentFromLMSIsAddedOnce() throws {
        let gist = try Harness.fixtureCopy()
        let input = #"{"course":"EC4207","title":"Homework Set #5","due":"2026-11-20T14:55:00Z","lms":139950}"#
        #expect(h.cli(["run", "assignment", "add", "--input", input], gist: gist).code == 0)
        let added = try #require(try h.file(GISTStore(url: gist)).assignments.first { $0.lmsId == 139950 })
        #expect(added.source == .lms)
        #expect(h.cli(["run", "assignment", "add", "--input", input], gist: gist).code != 0)
    }

    @Test func acceptAddsImportsAndMarks() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = dir.appending(path: "07_Flows.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        let due = ISO8601DateFormatter().date(from: "2026-11-20T14:55:00Z")!
        let items = [
            LMSAcceptItem(key: "assignment:139950", title: "Homework Set #5", due: due),
            LMSAcceptItem(key: "file:139200", file: pdf.path), LMSAcceptItem(key: "notice:23464"),
        ]
        let json = dir.appending(path: "items.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: json)
        try h.expectSame(["lms", "accept", "EC4207", "--items", json.path]) { _ in LMSAccept(course: course, items: items) }

        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code == 0)
        let file = try h.file(GISTStore(url: gist))
        #expect(file.assignments.contains { $0.lmsId == 139950 && $0.source == .lms })
        #expect(file.materials.contains { $0.path.hasPrefix("Lectures/") && $0.path.hasSuffix("07_Flows.pdf") })
        #expect(
            try GISTStore(url: gist).loadSettings().model.lms.handled.map(\.description) == [
                "assignment:139950", "file:139200", "notice:23464",
            ])
        #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code != 0)
    }

    @Test func acceptPutsAttachmentsInTheAssignmentFolderAsProblems() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let first = dir.appending(path: "1/slow_problem_2.pdf")
        let second = dir.appending(path: "2/slow_problem_2.pdf")
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("%PDF-1.4".utf8).write(to: url)
        }
        let items = [LMSAcceptItem(key: "assignment:139960", title: "Slow Problem #2", files: [first.path, second.path])]
        let json = dir.appending(path: "items.json")
        try JSONEncoder().encode(items).write(to: json)
        try h.expectSame(["lms", "accept", "EC4207", "--items", json.path]) { _ in LMSAccept(course: course, items: items) }

        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code == 0)
        let file = try h.file(GISTStore(url: gist))
        let added = try #require(file.assignments.first { $0.lmsId == 139960 })
        let folder = AssignmentFiles.path(of: added)
        let files = AssignmentFiles.materials(of: added, in: file.materials)
        #expect(Set(files.map(\.path)) == ["\(folder)/slow_problem_2.pdf", "\(folder)/slow_problem_2 2.pdf"])
        #expect(files.allSatisfy { $0.kind == .problem })
        #expect(file.materials.first { $0.id == added.problemMaterialId }?.path == "\(folder)/slow_problem_2.pdf")
    }

    @Test func acceptBesideAnAssignmentOfTheSameTitleKeepsBothProblemFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdf = dir.appending(path: "slow_problem_2.pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        let gist = try Harness.fixtureCopy()
        for lms in [139960, 139961] {
            let json = dir.appending(path: "\(lms).json")
            try JSONEncoder().encode([LMSAcceptItem(key: "assignment:\(lms)", title: "Slow Problem #2", files: [pdf.path])]).write(to: json)
            #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code == 0)
        }
        let file = try h.file(GISTStore(url: gist))
        let first = try #require(file.assignments.first { $0.lmsId == 139960 })
        let second = try #require(file.assignments.first { $0.lmsId == 139961 })
        let problem = { (a: Assignment) in file.materials.first { $0.id == a.problemMaterialId }?.path }
        #expect(problem(first) == "\(AssignmentFiles.path(of: first))/slow_problem_2.pdf")
        #expect(problem(second) == "\(AssignmentFiles.path(of: second))/slow_problem_2 2.pdf")
    }

    @Test func acceptRefusesAMissingAttachment() throws {
        let gist = try Harness.fixtureCopy()
        let json = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try Data(#"[{"key":"assignment:1","title":"A","files":["/nonexistent/a.pdf"]}]"#.utf8).write(to: json)
        #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code != 0)
        #expect(try !h.file(GISTStore(url: gist)).assignments.contains { $0.lmsId == 1 })
    }

    @Test func acceptRefusesAViewerOnlyFile() throws {
        let gist = try Harness.fixtureCopy()
        let json = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try Data(#"[{"key":"assignment:1","title":"A"},{"key":"file:2"}]"#.utf8).write(to: json)
        #expect(h.cli(["lms", "accept", "EC4207", "--items", json.path], gist: gist).code != 0)
        #expect(try !h.file(GISTStore(url: gist)).assignments.contains { $0.lmsId == 1 })
    }
}
