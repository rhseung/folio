import Foundation

// 카드 아래 줄에 적을, 노트가 기대는 것이다. 묶음의 이름이 이미 말하는 것은 빼서 카드에 다시 쓰지 않는다.
public struct NoteFacets: Sendable {
    public var sessions: [Session] = []
    public var units: [Unit] = []
    public var exam: Exam?
    public var tags: [String] = []

    public init(of meta: NoteMeta, in file: CourseFile, grouping: NoteGrouping) {
        switch NoteGroup(meta.kind) {
        case .classes:
            sessions = file.sessions(pointingAt: meta.id)
            if grouping != .unit { units = file.units(of: meta) }
        case .units:
            if grouping != .unit { units = file.units(of: meta) }
        case .exams:
            if grouping != .exam { exam = file.exams.first { $0.id == meta.examId } }
        case .free:
            break
        }
        if grouping != .tag { tags = meta.tags }
    }

    public var isEmpty: Bool { sessions.isEmpty && units.isEmpty && exam == nil && tags.isEmpty }
}
