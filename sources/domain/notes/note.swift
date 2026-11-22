import Foundation

extension CourseFile {
    public func meta(of entry: NoteEntry) -> NoteMeta {
        let sessions = sessions(pointingAt: entry.id)
        let units: [UUID] =
            switch entry.kind {
            case .unit: entry.unitIds
            case .rough, .review: taughtUnits(in: sessions)
            case .examSummary: exams.first { $0.id == entry.examId }.map { scope(of: $0) } ?? []
            case .free: []
            }
        var meta = NoteMeta(id: entry.id, kind: entry.kind, unitIds: units, examId: entry.examId, tags: entry.tags, math: entry.math)
        meta.sessionIds = sessions.map(\.id)
        return meta
    }

    // 회차마다 단원을 한 번만 구한다. 단원마다 모든 회차의 단원을 다시 구하면 노트 목록을 읽을 때마다 메인 스레드가 멈춘다.
    private func taughtUnits(in sessions: [Session]) -> [UUID] {
        let outline = UnitTree.outline(units).map(\.unit)
        let taught = Set(sessions.flatMap { unitIds(of: $0, outline: outline) })
        return outline.map(\.id).filter(taught.contains)
    }
}

public enum Note {
    public typealias ID = UUID
    public typealias Path = String
}
