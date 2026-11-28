import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation

extension Workspace {
    func donePlanItems(in courseIds: [UUID]) -> Set<UUID> {
        let events = courseIds.compactMap(course).flatMap { (try? $0.store.log.readAll()) ?? [] }
            .events(PlanCheckEvent.self)
        return ExamPlan.done(events)
    }

    func setPlanItems(_ items: [UUID], done: Bool, course id: UUID) {
        guard !items.isEmpty else { return }
        run(ExamPlanCheck(course: id, items: items, done: done))
    }

    // 과목들의 계획을 한 판으로 모은다. 시험이 가까운 과목의 줄이 앞에 온다. 과목의 계획 블록과 오늘 화면이 같은 값을 읽는다.
    func planBoard(_ courses: [LoadedCourse]) -> PlanBoard {
        let boards = courses.compactMap { course -> (start: Date, board: PlanBoard)? in
            guard let study = study(of: course.id) else { return nil }
            let exams = study.plannedExams(now: now, calendar: calendar)
            let board = study.planBoard(exams)
            return board.isEmpty ? nil : (exams.first?.start ?? .distantFuture, board)
        }
        return PlanBoard.merged(boards.sorted { $0.start < $1.start }.map(\.board))
    }
}
