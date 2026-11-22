import FolioCore
import Foundation

public struct SessionTableEntry: Sendable, Identifiable {
    public enum Item: Sendable {
        case session(Session)
        // 시간표에만 있고 아직 저장하지 않은 수업이다.
        case planned(Session)
        case exam(Exam)
        case deadline(Assignment)
    }

    public enum Look: Sendable, Equatable {
        case held, late, absent, cancelled, upcoming, next, exam, deadline, deadlineClosed
    }

    // 녹음과 복습 노트처럼 있는 것은 화면이 아이콘만 그리고, 할 일과 출결은 글로 쓴다. 고르는 규칙만 여기에 둔다.
    public enum Tag: Sendable, Hashable {
        case attendance(AttendanceState)
        case makeup
        case cancelled
        case unwrapped
        case recording(TimeInterval)
        case reviewNote
        case noReviewNote
        case scope(String)
    }

    public let item: Item
    public let date: Date
    public let day: LocalDate
    public let look: Look
    public let isMakeup: Bool
    public let tags: [Tag]
    // 회차는 단원, 시험과 과제는 제목이다. 단원이 없는 회차는 nil이고 화면이 "수업"으로 부른다.
    public let subject: String?
    public let pages: ClosedRange<Int>?
    // 시간표의 시작 시각과 다른 회차다. 화면은 이때만 블록에 시각을 다시 쓴다.
    public let offSchedule: Bool

    public var id: String {
        switch item {
        case .session(let s): s.id.uuidString
        case .planned(let s): "planned-\(s.date.timeIntervalSinceReferenceDate)"
        case .exam(let e): "exam-\(e.id)"
        case .deadline(let a): "deadline-\(a.id)"
        }
    }

    public var session: Session? {
        if case .session(let s) = item { return s }
        return nil
    }
}

extension SessionTableEntry {
    static func session(
        _ s: Session, planned: Bool, next: Bool, in file: CourseFile, now: Date, settings: Settings, asksWrapUp: Bool, calendar: Calendar
    ) -> SessionTableEntry {
        let schedule = file.course.schedule
        let attendance = planned ? nil : file.attendance.first { $0.sessionId == s.id }?.state
        let over = s.isOver(at: now, schedule: schedule, classMinutes: settings.classMinutes, calendar: calendar)
        let look: Look =
            if s.isCancelled { .cancelled } else if s.date > now { next ? .next : .upcoming } else if attendance == .absent {
                .absent
            } else if attendance == .late { .late } else { .held }

        var tags: [Tag] = []
        if s.isCancelled {
            tags = [.cancelled]
        } else if !planned {
            if let attendance, attendance != .present { tags.append(.attendance(attendance)) }
            if s.kind == .makeup { tags.append(.makeup) }
            if asksWrapUp, over, !s.isWrappedUp, !file.wrapUpGaps(of: s).isEmpty { tags.append(.unwrapped) }
            let recordings = file.recordings(of: s)
            if !recordings.isEmpty { tags.append(.recording(recordings.reduce(0) { $0 + $1.duration })) }
            switch file.review(of: s) {
            case .written, .writing: tags.append(.reviewNote)
            case .needed where over: tags.append(.noReviewNote)
            default: break
            }
        }

        let lectures = Set(file.lectureFiles.map(\.id))
        let pages = s.materials.lazy.filter { lectures.contains($0.materialId) }.compactMap { m -> ClosedRange<Int>? in
            guard let first = m.firstPage, let last = m.lastPage, first <= last else { return nil }
            return first...last
        }.first

        return SessionTableEntry(
            item: planned ? .planned(s) : .session(s), date: s.date, day: LocalDate(s.date, in: calendar), look: look,
            isMakeup: s.kind == .makeup, tags: tags, subject: planned ? nil : file.subject(of: s), pages: pages,
            offSchedule: s.slot(in: schedule, calendar: calendar) == nil)
    }

    static func exam(_ exam: Exam, at date: Date, in file: CourseFile, calendar: Calendar) -> SessionTableEntry {
        let units = file.scopeUnits(of: exam).map(\.title)
        let scope = exam.scopeText.isEmpty ? units.joined(separator: ", ") : exam.scopeText
        return SessionTableEntry(
            item: .exam(exam), date: date, day: LocalDate(date, in: calendar), look: .exam, isMakeup: false,
            tags: scope.isEmpty ? [] : [.scope(scope)], subject: exam.title, pages: nil, offSchedule: true)
    }

    // 낸 과제와 마감이 지난 과제는 지운 줄로 그린다.
    static func deadline(_ assignment: Assignment, at due: Date, now: Date, calendar: Calendar) -> SessionTableEntry {
        SessionTableEntry(
            item: .deadline(assignment), date: due, day: LocalDate(due, in: calendar),
            look: due < now || !assignment.status.isOpen ? .deadlineClosed : .deadline, isMakeup: false, tags: [],
            subject: assignment.title, pages: nil, offSchedule: true)
    }
}
