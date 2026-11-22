import FolioAI
import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class MakeProblemsModel {
    let workspace: Workspace
    let course: LoadedCourse
    let unit: FolioDomain.Unit
    var count = 5
    var draft: ProblemSheetDraft?
    var busy = false
    var failure: String?
    var keyRejected = false

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit, count: Int? = nil) {
        self.workspace = workspace
        self.course = course
        self.unit = unit
        if let count, count > 0 { self.count = count }
    }

    var hasKey: Bool { workspace.claudeReady && !keyRejected }
    var title: String { String(localized: .makeProblemsTitle(unit.title)) }
    var confirmTitle: String { String(localized: draft == nil ? .makeProblemsMake : .makeProblemsSave) }
    var canConfirm: Bool { hasKey && !busy && draft?.problems.isEmpty != true }
    var countOptions: [(Int, String)] {
        Set([3, 5, 10, count]).sorted().map { ($0, String(localized: .problemsCount($0))) }
    }

    // 본보기가 얼마나 있는지 알린다. 족보가 없으면 문제의 모양을 과목 자료에서만 짐작한다.
    var note: String {
        guard draft == nil else { return String(localized: .makeProblemsNoteSave) }
        let (past, wrong) = (examples.count, wrongOnes.count)
        return String(localized: .makeProblemsNote(past, wrong))
    }

    private var records: [CourseStudy.ProblemRecord] { workspace.study(of: course.id)?.problems(of: unit.id) ?? [] }
    private var examples: [Problem] { records.filter { $0.source == .pastExam }.map(\.problem) }
    private var wrongOnes: [Problem] { records.filter(\.status.needsWork).map(\.problem) }

    func confirm() -> Bool {
        guard let draft else {
            make()
            return false
        }
        let outline = course.file.units
        let problems = draft.problems.map { d in
            var p = d.problem(units: outline)
            // Claude가 단원 제목을 틀리게 적어도 이 단원을 위해 만든 문제이므로 이 단원에 잇는다.
            if p.unitIds.isEmpty { p.unitIds = [unit.id] }
            return p
        }
        return workspace.run(ProblemSetAdd(course: course.id, title: draft.title, source: .claude, problems: problems)) != nil
    }

    func make() {
        busy = true
        failure = nil
        let client = workspace.claude(for: course)
        let context = [ContextBuilder.courseSummary(course.file, now: workspace.now)] + noteContext()
        let (units, examples, wrong, count) = ([unit], examples, wrongOnes, count)
        Task {
            do {
                let sheet = try await client.writeProblemSheet(
                    units: units, examples: examples, wrong: wrong, count: count, context: context)
                draft = sheet
                if sheet.problems.isEmpty { failure = String(localized: .makeProblemsEmpty) }
            } catch ClaudeError.missingAPIKey {
                keyRejected = true
            } catch {
                failure = String(localized: .makeProblemsFailed("\(error)"))
            }
            busy = false
        }
    }

    private func noteContext() -> [ContextItem] {
        workspace.notes(for: unit, in: course.id).compactMap { note in
            (try? course.store.read(note)).map {
                ContextItem(id: "note:\(note.title)", title: "노트 \(note.title)", tier: .focus, text: $0)  // strings: data, Claude가 읽는 제목
            }
        }
    }
}
