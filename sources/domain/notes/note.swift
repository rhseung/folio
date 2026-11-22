import Foundation

extension CourseFile {
    public func meta(of entry: NoteEntry) -> NoteMeta {
        let sessions = sessions(pointingAt: entry.id)
        let units: [UUID] =
            switch entry.kind {
            case .unit: entry.unitIds
            case .rough, .review:
                UnitTree.outline(self.units).map(\.unit.id).filter { u in sessions.contains { unitIds(of: $0).contains(u) } }
            case .examSummary: exams.first { $0.id == entry.examId }.map { scope(of: $0) } ?? []
            case .free: []
            }
        var meta = NoteMeta(id: entry.id, kind: entry.kind, unitIds: units, examId: entry.examId, tags: entry.tags, math: entry.math)
        meta.sessionIds = sessions.map(\.id)
        return meta
    }
}

public enum Note {
    public typealias ID = UUID
    public typealias Path = String
}
