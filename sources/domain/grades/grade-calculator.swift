import Foundation

// 점수는 모두 0에서 100 사이이고, 비율은 0에서 1 사이이다.
public enum GradeCalculator {
    public struct ComponentResult: Sendable, Equatable {
        public var componentId: UUID
        public var ratio: Double?
        public var completion: Double
        public var z: Double?
        public var zEstimated = false
        public var meanGap: Double?
    }

    public struct CourseScore: Sendable, Equatable {
        public var components: [ComponentResult]
        public var secured: Double
        public var projected: Double?
        public var z: Double?
        public var zEstimated = false
        public var meanGap: Double?
        public var remainingWeight: Double
    }

    // `expected`는 면제한 점수를 뺀 전체 점수 개수이다. 이 값이 있으면 `dropLowest`는 `expected - n`을 넘은 점수만큼만
    // 뺀다. 퀴즈 9개 중 2개를 빼면 7번째까지는 빼지 않고, 8번째에서 하나를 뺀다.
    public static func ratio(of entries: [ScoreEntry], by aggregation: Aggregation, expected: Int? = nil) -> Double? {
        let counted = entries.filter { !$0.excused && $0.max > 0 }
        guard !counted.isEmpty else { return nil }
        let ratios = counted.map { $0.score / $0.max }
        func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(xs.count) }
        switch aggregation {
        case .sum:
            return counted.reduce(0) { $0 + $1.score } / counted.reduce(0) { $0 + $1.max }
        case .mean:
            return mean(ratios)
        case .single:
            return ratios.last
        case .dropLowest(let n):
            // 점수를 모두 빼지 않도록, 점수가 n개 이하이면 모두 센다.
            let drops = expected.map { Swift.max(0, Swift.min(n, ratios.count - ($0 - n))) } ?? (ratios.count > n ? n : 0)
            return mean(Array(ratios.sorted().dropFirst(Swift.max(0, Swift.min(drops, ratios.count - 1)))))
        case .bestOf(let n):
            return mean(Array(ratios.sorted(by: >).prefix(Swift.max(n, 1))))
        }
    }

    public static func score(components: [GradeComponent], entries: [ScoreEntry]) -> CourseScore {
        // 수업은 평균만 알리고 표준편차는 알리지 않는 일이 많다. 그런 점수는 둘 다 알린 이 과목의 다른 점수에서 만점
        // 대비 퍼짐을 빌려 온다. 빌려 올 점수가 없으면 z가 없고, 평균과의 차이만 센다.
        let spreads = entries.compactMap { e -> Double? in
            guard !e.excused, e.mean != nil, e.max > 0, let sd = e.stdDev, sd > 0 else { return nil }
            return sd / e.max
        }
        let spread = spreads.isEmpty ? nil : spreads.reduce(0, +) / Double(spreads.count)
        let results = components.map { component -> ComponentResult in
            let own = entries.filter { $0.componentId == component.id }
            let counted = own.filter { !$0.excused }
            let expected = component.count.map { Swift.max($0 - own.filter(\.excused).count, 1) }
            let completion: Double = counted.isEmpty ? 0 : expected.map { Swift.min(1, Double(counted.count) / Double($0)) } ?? 0
            let withMean = counted.filter { $0.mean != nil && $0.max > 0 }
            let zs = withMean.compactMap { e -> (z: Double, estimated: Bool)? in
                let gap = e.score - e.mean!
                if let sd = e.stdDev, sd > 0 { return (gap / sd, false) }
                return spread.map { (gap / ($0 * e.max), true) }
            }
            let gaps = withMean.map { ($0.score - $0.mean!) / $0.max }
            return ComponentResult(
                componentId: component.id,
                ratio: ratio(of: own, by: component.aggregation, expected: expected),
                completion: completion,
                z: zs.isEmpty ? nil : zs.map(\.z).reduce(0, +) / Double(zs.count),
                zEstimated: zs.contains { $0.estimated },
                meanGap: gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count)
            )
        }
        let weights = Dictionary(keepingFirst: components.map { ($0.id, $0.weight) })
        let graded = results.filter { $0.ratio != nil }
        let secured = graded.reduce(0) { $0 + weights[$1.componentId]! * $1.ratio! * $1.completion }
        let remainingWeight = results.reduce(0) { $0 + weights[$1.componentId]! * (1 - $1.completion) }

        let share = { (r: ComponentResult) in components.first { $0.id == r.componentId }?.count == nil ? 1 : r.completion }
        let gradedWeight = graded.reduce(0) { $0 + weights[$1.componentId]! * share($1) }
        let overall = gradedWeight > 0 ? graded.reduce(0) { $0 + weights[$1.componentId]! * $1.ratio! * share($1) } / gradedWeight : nil
        let projected = overall.map { overall in
            results.reduce(0) { sum, r in
                let w = weights[r.componentId]!
                let rate = r.ratio ?? overall
                return sum + w * rate
            }
        }

        let withZ = results.filter { $0.z != nil }
        let zWeight = withZ.reduce(0) { $0 + weights[$1.componentId]! }
        let z = zWeight > 0 ? withZ.reduce(0) { $0 + weights[$1.componentId]! * $1.z! } / zWeight : nil
        let withGap = results.filter { $0.meanGap != nil }
        let gapWeight = withGap.reduce(0) { $0 + weights[$1.componentId]! }
        let gap = gapWeight > 0 ? withGap.reduce(0) { $0 + weights[$1.componentId]! * $1.meanGap! } / gapWeight : nil

        return CourseScore(
            components: results, secured: secured, projected: projected, z: z,
            zEstimated: withZ.contains { $0.zEstimated }, meanGap: gap, remainingWeight: remainingWeight)
    }

    public static func requiredAverage(for target: Double, given score: CourseScore) -> Double? {
        guard score.remainingWeight > 0 else { return nil }
        return (target - score.secured) / score.remainingWeight * 100
    }

    // MARK: Relative standing

    public struct Standing: Sendable, Equatable {
        public var above: Double
        public var cutZ: Double
        public var z: Double
        public var inTopGrade: Bool { z >= cutZ }

        static func cdf(_ z: Double) -> Double { 0.5 * (1 + erf(z / 2.squareRoot())) }
    }

    public static func standing(z: Double, topGradeRatio ratio: Double) -> Standing {
        let share = Swift.min(Swift.max(ratio, 0.001), 0.999)
        var lo = -8.0, hi = 8.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if 1 - Standing.cdf(mid) > share { lo = mid } else { hi = mid }
        }
        return Standing(above: 1 - Standing.cdf(z), cutZ: (lo + hi) / 2, z: z)
    }

    // 대칭 곡선에서 A 비율이 50%이면 A 기준선은 평균에 있고, 비율이 더 크면 평균 아래, 더 작으면 평균 위에 있다.
    // 그래서 평균의 한쪽은 이것만으로 정해지고, 다른 쪽은 퍼짐이 있어야 하므로 nil이다.
    public static func inTopGrade(meanGap: Double, topGradeRatio ratio: Double) -> Bool? {
        if meanGap >= 0, ratio >= 0.5 { return true }
        if meanGap <= 0, ratio <= 0.5 { return false }
        return nil
    }

    // MARK: Attendance and letter grades

    public static func absences(in attendance: [Attendance], policy: GradePolicy) -> Int {
        let absent = attendance.filter { $0.state == .absent }.count
        guard let n = policy.latesPerAbsence, n > 0 else { return absent }
        return absent + attendance.filter { $0.state == .late }.count / n
    }

    public static func attendanceCap(absences: Int, policy: GradePolicy) -> AttendanceCap? {
        policy.attendanceCap.filter { absences >= $0.absences }.max { $0.absences < $1.absences }
    }

    public static func nextCap(absences: Int, policy: GradePolicy) -> AttendanceCap? {
        policy.attendanceCap.filter { $0.absences > absences }.min { $0.absences < $1.absences }
    }

    public static func absencesUntilNextCap(absences: Int, policy: GradePolicy) -> Int? {
        nextCap(absences: absences, policy: policy).map { $0.absences - absences }
    }

    public static func letterGrade(score: Double, absences: Int, policy: GradePolicy, catalog: Catalog) -> LetterGrade? {
        let byScore = policy.cutoffs.sorted { $0.minScore > $1.minScore }.first { score >= $0.minScore }.flatMap { catalog.grade($0.grade) }
        guard let cap = attendanceCap(absences: absences, policy: policy).flatMap({ catalog.grade($0.maxGrade) }) else {
            return byScore
        }
        guard let earned = byScore else { return cap }
        return (earned.points ?? 0) > (cap.points ?? 0) ? cap : earned
    }
}

extension GradeComponent {
    var count: Int? { expectedCount ?? (aggregation == .single ? 1 : nil) }
}
