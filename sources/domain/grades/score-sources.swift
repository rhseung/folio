import Foundation

public enum ScoreSource: Hashable, Sendable {
    case none, assignment(UUID), exam(UUID)
}

extension ScoreEntry {
    public var source: ScoreSource {
        get { assignmentId.map { .assignment($0) } ?? examId.map { .exam($0) } ?? .none }
        set {
            (assignmentId, examId) =
                switch newValue {
                case .none: (nil, nil)
                case .assignment(let a): (a, nil)
                case .exam(let e): (nil, e)
                }
        }
    }
}

extension CourseFile {
    public func counts(_ source: ScoreSource, toward component: UUID) -> Bool {
        switch source {
        case .none: return false
        case .assignment(let id):
            guard let a = assignments.first(where: { $0.id == id }) else { return false }
            if let g = a.componentGroup { return components.contains { $0.id == component && $0.group == g } }
            return a.componentId == component
        case .exam(let id): return exams.first { $0.id == id }?.componentId == component
        }
    }

    /// Assignments then exams, each with the ones counting toward the component first, then by date.
    public func scoreSources(for component: UUID) -> [ScoreSource] {
        let a = assignments.sorted { x, y in
            let (cx, cy) = (counts(.assignment(x.id), toward: component), counts(.assignment(y.id), toward: component))
            return cx != cy ? cx : (x.due ?? .distantFuture) < (y.due ?? .distantFuture)
        }
        let e = exams.sorted { x, y in
            let (cx, cy) = (x.componentId == component, y.componentId == component)
            return cx != cy ? cx : (x.start ?? .distantFuture) < (y.start ?? .distantFuture)
        }
        return a.map { .assignment($0.id) } + e.map { .exam($0.id) }
    }

    public func title(of source: ScoreSource) -> String? {
        switch source {
        case .none: nil
        case .assignment(let id): assignments.first { $0.id == id }?.title
        case .exam(let id): exams.first { $0.id == id }?.title
        }
    }

    /// The assignment sheet shows one score per component, so a second score for the same assignment and component
    /// would be hidden there and overwritten by its next save.
    public func hasScore(_ source: ScoreSource, in component: UUID, other entry: UUID? = nil) -> Bool {
        source != .none && scores.contains { $0.id != entry && $0.componentId == component && $0.source == source }
    }

    /// A score means the assignment was graded, whatever its status said, from whichever page the score came.
    public mutating func markGraded(_ assignment: UUID, device: DeviceID, now: Date) {
        guard scores.contains(where: { $0.assignmentId == assignment }),
            let i = assignments.firstIndex(where: { $0.id == assignment }), assignments[i].status != .graded
        else { return }
        assignments[i].status = .graded
        assignments[i].touch(by: device, at: now)
    }
}
