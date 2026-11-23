import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

// 문제집을 만들기 전에 고른 문제의 그림을 Claude에게 다시 그리게 하고, 풀이가 없는 문제의 풀이를 쓰게 한다(#577).
// 결과는 액션으로 써서 다음 문제집은 다시 묻지 않는다. 실패한 항목은 문제지에서 자른 그림과 원래 풀이로 남는다.
@MainActor
struct ProblemArtDrawing {
    let workspace: Workspace
    let course: UUID
    let client: ClaudeClient

    // 한 번에 맡기는 항목 수다. 문제마다 1분 가까이 걸려서 차례로 하면 문제집 하나에 몇 분이 걸린다.
    static let parallel = 4

    struct Outcome {
        var done = 0
        var failed = 0
    }

    static func jobs(_ course: LoadedCourse, picked: [UUID]) -> [ProblemArt.Job] {
        let sheets = Set(
            course.file.problemSets.filter { s in course.file.materials.contains { $0.id == s.materialId && $0.isPDF } }.map(\.id))
        return ProblemArt.jobs(
            sets: course.file.problemSets, picked: Set(picked), sheets: sheets, drawn: Set(course.store.problemArt().keys))
    }

    // 지문을 먼저 그린다. 문제의 풀이용 그림이 다시 그린 지문의 그림 위에 그려야 하기 때문이다.
    func run(_ jobs: [ProblemArt.Job], progress: @escaping (Int) -> Void) async -> Outcome {
        var outcome = Outcome()
        let stems = jobs.filter { $0.stem != nil }, problems = jobs.filter { $0.problem != nil }
        // 넷씩 묶어 함께 맡긴다. 각 Task는 main actor에서 돌고 Claude의 답을 기다리는 동안 다른 Task가 돈다. task group의
        // `addTask`는 Swift 6.4의 region isolation 검사가 이 struct의 메서드를 부르는 것을 컴파일하지 못한다.
        for batch in [stems, problems] {
            for start in stride(from: 0, to: batch.count, by: Self.parallel) {
                let tasks = batch[start..<min(start + Self.parallel, batch.count)].map { job in Task { await draw(job) } }
                for task in tasks {
                    outcome.done += 1
                    if await !task.value { outcome.failed += 1 }
                    progress(outcome.done)
                }
            }
        }
        return outcome
    }

    private func draw(_ job: ProblemArt.Job) async -> Bool {
        guard let loaded = workspace.course(course), let set = loaded.file.problemSets.first(where: { $0.id == job.set }) else {
            return false
        }
        let sheet = loaded.file.materials.first { $0.id == set.materialId && $0.isPDF }.map { loaded.store.fileURL($0.path) }
        let regions = job.figures.isEmpty ? job.stems.reversed().first { !$0.figures.isEmpty }?.figures ?? [] : job.figures
        let crops = job.draws ? sheet.map { url in regions.compactMap { PDFRegionRenderer.png(url, region: $0) } } ?? [] : []
        let art = loaded.store.problemArt()
        let stemFigure = job.stems.reversed().lazy.compactMap { art[$0.id]?.model.figure }.first

        let korean = FigureStyle.allowsKorean(loaded.file.course, catalog: workspace.catalog)
        do {
            var draft = try await client.drawProblemArt(job, crops: crops, stemFigure: stemFigure)
            // 그리지 않는 항목은 그림을 쓰지 않으므로 검사도, 고쳐 달라는 재요청도 하지 않는다.
            let problems = job.draws ? Self.problems(draft, korean: korean) : []
            if !problems.isEmpty {
                draft = try await client.drawProblemArt(job, crops: crops, stemFigure: stemFigure, previous: draft, problems: problems)
            }
            // 고쳐도 검사에 걸리는 그림이 있으면 쓰지 않는다. 파일이 있으면 다음 문제집이 다시 그리지 않으므로, 한 번의 실패가
            // 굳지 않게 실패로만 세어 다음에 다시 맡긴다. 이번 문제집에는 자른 그림이 들어간다. 그릴 것이 없다는 답(null)은 쓴다.
            let rejected = job.draws && !Self.problems(draft, korean: korean).isEmpty
            if job.draws, !rejected {
                _ = try workspace.runThrowing(
                    ProblemFigureWrite(
                        course: course, set: job.set, number: job.number, figure: draft.figure,
                        solutionFigure: draft.solutionFigure))
            }
            if job.writesSolution, var p = job.problem,
                let solution = draft.solution?.trimmingCharacters(in: .whitespacesAndNewlines), !solution.isEmpty
            {
                p.solution = solution
                _ = try workspace.runThrowing(ProblemSave(course: course, set: job.set, problems: [p]))
            }
            return !rejected
        } catch {
            return false
        }
    }

    private static func problems(_ draft: ProblemArtDraft, korean: Bool) -> [String] {
        [draft.figure, draft.solutionFigure].compactMap { $0 }.flatMap { svg -> [String] in
            do { return try NoteFigureFinish.finish(svg, korean: korean).problems.map(\.message) } catch { return ["\(error)"] }
        }
    }
}
