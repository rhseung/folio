import FolioCore
import Foundation

// 계산으로 채울 수 없는 연결이다. 회차의 단원, 배운 범위, 시험 범위처럼 다른 칸에서 나오는 값은 계산하므로 여기에
// 넣지 않고, 사용자가 한 번 적어 주어야 계산이 돌아가는 자리만 넣는다.
public enum CourseLinkGap: Hashable, Sendable, Codable {
    // 진도 쪽이 있는데 단원 쪽 구간이 없어 그 쪽이 어느 단원인지 읽을 수 없는 렉처
    case unsplitLecture(material: UUID)
    case examWithoutDate(exam: UUID)
    // 시험 전에 수업을 했는데 그 수업에서 배운 단원을 하나도 읽을 수 없다
    case examScopeUnknown(exam: UUID)
    // 단원 노트에 단원이, 시험 정리 노트에 시험이, 수업 노트에 회차가 없다. 자유 노트는 걸 데가 없는 것이 맞아 넣지 않는다.
    case looseNote(note: UUID)
    // 휴강한 회차가 노트를 쥐고 있어 노트가 회차 목록에 없는 수업을 가리킨다
    case cancelledSessionNote(session: UUID, note: UUID)

    // 연결이 비어 있는 것이 아니라 틀린 곳을 가리키는 것이다. `folio check`는 이것만 문제로 본다.
    public var isDangling: Bool {
        if case .cancelledSessionNote = self { true } else { false }
    }
}

extension CourseFile {
    public func linkGaps(now: Date, today: LocalDate, calendar: Calendar) -> [CourseLinkGap] {
        var gaps: [CourseLinkGap] = []
        let split = Set(units.flatMap(\.lecturePages).map(\.materialId))
        for lecture in lectureFiles where !split.contains(lecture.id) {
            if sessions.contains(where: { s in !s.isCancelled && s.materials.contains { $0.materialId == lecture.id && $0.pages != nil } })
            {
                gaps.append(.unsplitLecture(material: lecture.id))
            }
        }

        for exam in exams.sorted(by: { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) })
        where !exam.isOver(now: now, today: today, calendar: calendar) && scope(of: exam).isEmpty {
            guard let start = exam.start else {
                gaps.append(.examWithoutDate(exam: exam.id))
                continue
            }
            let from = previousExam(before: exam)?.start
            let held = sessions.contains { s in !s.isCancelled && s.date <= now && s.date < start && from.map { s.date >= $0 } ?? true }
            if held { gaps.append(.examScopeUnknown(exam: exam.id)) }
        }

        let knownUnits = Set(units.map(\.id))
        for note in notes.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let loose =
                switch note.kind {
                case .unit: !note.unitIds.contains(where: knownUnits.contains)
                case .examSummary: !exams.contains { $0.id == note.examId }
                case .rough, .review: sessions(pointingAt: note.id).isEmpty
                case .free: false
                }
            if loose { gaps.append(.looseNote(note: note.id)) }
        }

        for session in sessions.sorted(by: Session.inOrder) where session.isCancelled {
            for note in [session.roughNoteId, session.reviewNoteId].compactMap({ $0 }) {
                gaps.append(.cancelledSessionNote(session: session.id, note: note))
            }
        }
        return gaps
    }

    public func describe(_ gap: CourseLinkGap, calendar: Calendar) -> String {
        let file = { (id: UUID) in self.materials.first { $0.id == id }.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "" }
        let exam = { (id: UUID) in self.exams.first { $0.id == id }?.title ?? "" }
        let note = { (id: UUID) in self.notes.first { $0.id == id }?.path ?? "" }
        switch gap {
        case .unsplitLecture(let m): return String(localized: .gapsUnsplitLecture(file(m)))
        case .examWithoutDate(let e): return String(localized: .gapsExamWithoutDate(exam(e)))
        case .examScopeUnknown(let e): return String(localized: .gapsExamScopeUnknown(exam(e)))
        case .looseNote(let n): return String(localized: .gapsLooseNote(note(n)))
        case .cancelledSessionNote(let s, let n):
            let day = sessions.first { $0.id == s }.map { self.day(of: $0, calendar: calendar) } ?? ""
            return String(localized: .gapsCancelledSessionNote(day, note(n)))
        }
    }
}
