import FolioCore
import Foundation

// 시험의 정리 노트를 공부 기간에 놓는다(#573 "계획"). 기간이나 정리 노트 목록이 바뀔 때만 부르고, 공부일이 바뀌었다고 다시
// 놓지 않는다. 못 한 항목은 뒤 항목을 밀지 않고 그날에 남아 오늘에 얹혀 보인다.
public enum ExamPlanner {
    // `mocks`는 과목의 족보 묶음 수다. 기간 뒤가 모의고사면 하루 한 벌씩 이 수까지 놓는다.
    public static func plan(
        current: [ExamPlanItem], notes: ExamPlanNotes, period: ExamPlanPeriod, mocks: Int, today: LocalDate, examDay: LocalDate,
        isDone: (ExamPlanItem) -> Bool
    ) -> [ExamPlanItem] {
        let proofOf = Dictionary(notes.notes.map { ($0.id, $0.proof) }, uniquingKeysWith: { a, _ in a })
        let missing = Set(notes.missing)
        // 목록에서 빠진 노트, 노트가 생긴 단원, 정리류 블록이 없어진 노트의 증명은 더 놓을 대상이 아니다.
        func stale(_ item: ExamPlanItem) -> Bool {
            switch item.target.kind {
            case .note:
                guard let proof = item.target.id.flatMap({ proofOf[$0] }) else { return true }
                return item.target.stage == .proof && !proof
            case .makeNote: return !(item.target.id.map(missing.contains) ?? false)
            case .mock, .custom: return false
            }
        }
        // 끝낸 항목과 사용자가 옮기거나 더하거나 뺀 항목은 그대로 둔다. 체크 기록이 항목 id를 가리키므로 끝낸 항목은 새로
        // 만들지 않는다.
        let kept = current.filter { $0.target.kind == .custom || isDone($0) || (($0.isEdited || $0.isRemoved) && !stale($0)) }
        let held = Set(kept.map(\.target))
        // 다시 놓는 항목도 id를 지킨다. 화면의 줄이 다시 놓을 때마다 새 줄로 바뀌지 않는다.
        var reusable = Dictionary(grouping: current.filter { item in !kept.contains { $0.id == item.id } }, by: \.target)
        func item(_ day: LocalDate, _ target: ExamPlanTarget) -> ExamPlanItem {
            let id = reusable[target]?.isEmpty == false ? reusable[target]?.removeFirst().id : nil
            return ExamPlanItem(id: id ?? UUID(), day: day, target: target)
        }

        var out = kept
        let first = max(period.start, today)
        let days = period.end >= first ? first.days(until: period.end) + 1 : 0
        // 기간이 이미 지났으면 끝낼 날에 놓는다. 지난 날의 항목이라 오늘에 밀림으로 얹힌다.
        let anchor = days > 0 ? first : period.end

        for unit in notes.missing where !held.contains(.makeNote(unit)) { out.append(item(anchor, .makeNote(unit))) }

        let open = notes.notes.compactMap { note -> (id: UUID, stages: [PlanStage])? in
            let stages = PlanStage.stages(proof: note.proof).filter { !held.contains(.note(note.id, $0)) }
            return stages.isEmpty ? nil : (note.id, stages)
        }
        for (i, note) in open.enumerated() {
            let day = days > 0 ? first.adding(days: i * days / open.count) : anchor
            for stage in note.stages { out.append(item(day, .note(note.id, stage))) }
        }

        if period.after == .mock {
            let taken = kept.filter { $0.target.kind == .mock }
            let busy = Set(taken.filter { !$0.isRemoved }.map(\.day))
            var left = max(mocks - taken.count, 0)
            var day = max(period.end.adding(days: 1), today)
            while left > 0, day < examDay {
                if !busy.contains(day) {
                    out.append(item(day, .mock))
                    left -= 1
                }
                day = day.adding(days: 1)
            }
        }
        // 같은 날의 항목은 넣은 순서를 지킨다.
        return out.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }.map(\.element)
    }
}
