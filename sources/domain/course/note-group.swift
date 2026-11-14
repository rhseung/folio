import Foundation

public enum NoteGroup: CaseIterable, Sendable {
    case classes, exams, units, free

    public init(_ kind: NoteKind) {
        switch kind {
        case .rough, .review: self = .classes
        case .examSummary: self = .exams
        case .unit: self = .units
        case .free: self = .free
        }
    }

    public static func grouped<Note>(
        _ notes: [Note], meta: (Note) -> NoteMeta, title: (Note) -> String,
        in file: CourseFile
    ) -> [(group: NoteGroup, notes: [Note])] {
        allCases.compactMap { group in
            let members = notes.filter { NoteGroup(meta($0).kind) == group }
            return members.isEmpty ? nil : (group, group.sorted(members, meta: meta, title: title, in: file))
        }
    }

    public func sorted<Note>(_ notes: [Note], meta: (Note) -> NoteMeta, title: (Note) -> String, in file: CourseFile) -> [Note] {
        func byTitle(_ a: Note, _ b: Note) -> Bool { title(a).localizedStandardCompare(title(b)) == .orderedAscending }

        switch self {
        case .classes:
            let keyed = notes.map { (note: $0, kind: meta($0).kind, last: file.sessions(pointingAt: meta($0).id).last) }
            return keyed.sorted { a, b in
                switch (a.last, b.last) {
                case let (x?, y?) where x.id != y.id: x.date > y.date
                case (_?, nil): true
                case (nil, _?): false
                default: a.kind == b.kind ? byTitle(a.note, b.note) : a.kind == .rough
                }
            }.map(\.note)
        case .exams:
            let keyed = notes.map { n in (note: n, start: file.exams.first { $0.id == meta(n).examId }?.start ?? .distantFuture) }
            return keyed.sorted { a, b in a.start != b.start ? a.start < b.start : byTitle(a.note, b.note) }.map(\.note)
        case .units, .free:
            return notes.sorted(by: byTitle)
        }
    }
}
