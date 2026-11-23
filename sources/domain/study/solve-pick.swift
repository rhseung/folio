import FolioCore
import Foundation

// 풀기 화면의 "문제" 고르기다. 화면은 이 값을 바꾸기만 하고 어떤 문제가 들어가는지는 여기서 정한다.
public struct SolvePick: Sendable, Equatable {
    public enum Filter: String, Sendable, CaseIterable {
        // 오답과 다시 확인할 문제다.
        case wrong
        case untried
        case all
    }

    public enum Order: String, Sendable, CaseIterable {
        case byUnit
        // 섞으면 단원 표시를 가린다. 어느 단원 문제인지 모르고 푸는 연습이다.
        case shuffled
    }

    public var filter: Filter
    public var units: Set<UUID>
    public var sources: Set<ProblemSource>
    public var sets: Set<UUID>
    public var count: Int?
    public var order: Order
    // 화면에서 푸는 풀기(타이핑)는 화면에서 푸는 형식만 고른다.
    public var onScreenOnly: Bool

    public init(
        filter: Filter = .all, units: Set<UUID> = [], sources: Set<ProblemSource> = [], sets: Set<UUID> = [], count: Int? = nil,
        order: Order = .byUnit, onScreenOnly: Bool = false
    ) {
        self.filter = filter
        self.units = units
        self.sources = sources
        self.sets = sets
        self.count = count
        self.order = order
        self.onScreenOnly = onScreenOnly
    }

    public func matches(_ r: CourseStudy.ProblemRecord) -> Bool {
        switch filter {
        case .wrong: guard r.status.needsWork else { return false }
        case .untried: guard !r.solved else { return false }
        case .all: break
        }
        if !units.isEmpty, units.isDisjoint(with: r.problem.unitIds) { return false }
        if !sources.isEmpty, !sources.contains(r.source) { return false }
        if !sets.isEmpty, !sets.contains(r.setId) { return false }
        if onScreenOnly, !r.problem.format.onScreen { return false }
        return true
    }

    // 같은 씨앗이면 같은 순서다. 시트를 다시 그려도 고른 문제가 바뀌지 않게 씨앗은 시트가 들고 있다.
    public func pick(from study: CourseStudy, seed: UInt64) -> [CourseStudy.ProblemRecord] {
        let unitOrder = Dictionary(
            UnitTree.outline(study.file.units).enumerated().map { ($0.element.unit.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let records = study.allProblems.filter(matches)
        var ordered: [CourseStudy.ProblemRecord]
        switch order {
        case .byUnit:
            let rank = { (r: CourseStudy.ProblemRecord) in r.problem.unitIds.compactMap { unitOrder[$0] }.min() ?? Int.max }
            ordered = records.enumerated().sorted { a, b in (rank(a.element), a.offset) < (rank(b.element), b.offset) }.map(\.element)
        case .shuffled:
            var rng = SeededGenerator(seed: seed)
            ordered = records.shuffled(using: &rng)
        }
        if let count, count < ordered.count { ordered = Array(ordered.prefix(max(count, 0))) }
        return ordered
    }
}
