import Foundation

/// docs/SPEC.md "성적 계산". All scores are on a 0-100 scale; ratios are 0-1.
public enum GradeCalculator {
    public struct ComponentResult: Sendable, Equatable {
        public var componentId: UUID
        /// Earned ratio over the scores so far, after the aggregation rule. Nil before the first score.
        public var ratio: Double?
        /// Share of the component already graded (0-1).
        public var completion: Double
        /// Mean z-score of entries that publish a class mean, with or without a standard deviation (see `zEstimated`).
        public var z: Double?
        /// Some z here came from a spread borrowed from the course's other scores, not a published standard deviation.
        public var zEstimated = false
        /// Mean of (score - class mean) / max over entries that publish a mean: above zero is above the class mean.
        public var meanGap: Double?
    }

    public struct CourseScore: Sendable, Equatable {
        public var components: [ComponentResult]
        /// Only what is already earned; ungraded work counts as 0.
        public var secured: Double
        /// Ungraded work assumed to go like the work graded so far. Nil before any score.
        public var projected: Double?
        /// Weight-averaged z-score over components that have one.
        public var z: Double?
        public var zEstimated = false
        /// Weight-averaged `meanGap`: its sign alone says above or below the class mean, no standard deviation needed.
        public var meanGap: Double?
        /// Percent of the final score still to be graded.
        public var remainingWeight: Double
    }

    /// - Parameter expected: how many scores the component will have in all, excused ones left out. With it, `dropLowest`
    ///   drops only as many as the scores past `expected - n`: of 9 quizzes dropping 2, none until the 7th, one at the 8th.
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
            // Never drop everything: with n or fewer scores, all of them count.
            let drops = expected.map { Swift.max(0, Swift.min(n, ratios.count - ($0 - n))) } ?? (ratios.count > n ? n : 0)
            return mean(Array(ratios.sorted().dropFirst(Swift.max(0, Swift.min(drops, ratios.count - 1)))))
        case .bestOf(let n):
            return mean(Array(ratios.sorted(by: >).prefix(Swift.max(n, 1))))
        }
    }

    public static func score(components: [GradeComponent], entries: [ScoreEntry]) -> CourseScore {
        // Classes often publish a mean but no standard deviation. Such a score borrows the spread, as a share of the max,
        // that the course's scores with both show; with none, it has no z and only its gap from the mean counts.
        let spreads = entries.compactMap { e -> Double? in
            guard !e.excused, e.mean != nil, e.max > 0, let sd = e.stdDev, sd > 0 else { return nil }
            return sd / e.max
        }
        let spread = spreads.isEmpty ? nil : spreads.reduce(0, +) / Double(spreads.count)
        let results = components.map { component -> ComponentResult in
            let own = entries.filter { $0.componentId == component.id }
            let counted = own.filter { !$0.excused }
            let expected = component.count.map { Swift.max($0 - own.filter(\.excused).count, 1) }
            // Without a count, how much is left is unknown, so none of it is secured yet; it still shapes the projection.
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

        // Components without a count weigh in fully here, as their scores so far are all there is to go on.
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

        return CourseScore(components: results, secured: secured, projected: projected, z: z,
                           zEstimated: withZ.contains { $0.zEstimated }, meanGap: gap, remainingWeight: remainingWeight)
    }

    /// Average percent needed on everything still ungraded to finish at `target`. Nil when nothing remains.
    /// Over 100 means the target is out of reach; 0 or below means it is already secured.
    public static func requiredAverage(for target: Double, given score: CourseScore) -> Double? {
        guard score.remainingWeight > 0 else { return nil }
        return (target - score.secured) / score.remainingWeight * 100
    }

    // MARK: Relative standing

    public struct Standing: Sendable, Equatable {
        /// Share of the class expected above this z, from 0 to 1.
        public var above: Double
        /// The z an A takes: the A share's cut on a normal curve.
        public var cutZ: Double
        public var z: Double
        public var inTopGrade: Bool { z >= cutZ }

        static func cdf(_ z: Double) -> Double { 0.5 * (1 + erf(z / 2.squareRoot())) }
    }

    /// Where a weighted z lands in a relatively graded class, taking scores as normally distributed: the published
    /// mean and standard deviation are all there is, so the curve is an assumption, not the class's real spread.
    public static func standing(z: Double, topGradeRatio ratio: Double) -> Standing {
        let share = Swift.min(Swift.max(ratio, 0.001), 0.999)
        // Bisection: Φ is monotone, and this needs no more than a few digits.
        var lo = -8.0, hi = 8.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if 1 - Standing.cdf(mid) > share { lo = mid } else { hi = mid }
        }
        return Standing(above: 1 - Standing.cdf(z), cutZ: (lo + hi) / 2, z: z)
    }

    /// In the A share or not, from which side of the class mean the scores sit, when no z is known. A symmetric curve
    /// puts the A cut at the mean for a 50% share, below it for more and above it for less, so one side of the mean
    /// settles it; the other side needs the spread and is nil.
    public static func inTopGrade(meanGap: Double, topGradeRatio ratio: Double) -> Bool? {
        if meanGap >= 0, ratio >= 0.5 { return true }
        if meanGap <= 0, ratio <= 0.5 { return false }
        return nil
    }

    // MARK: Attendance and letter grades

    /// Absences toward the caps: each 결석, plus one for every `latesPerAbsence` 지각. 공결 never counts.
    public static func absences(in attendance: [Attendance], policy: GradePolicy) -> Int {
        let absent = attendance.filter { $0.state == .absent }.count
        guard let n = policy.latesPerAbsence, n > 0 else { return absent }
        return absent + attendance.filter { $0.state == .late }.count / n
    }

    /// The strictest cap reached so far, if any.
    public static func attendanceCap(absences: Int, policy: GradePolicy) -> AttendanceCap? {
        policy.attendanceCap.filter { absences >= $0.absences }.max { $0.absences < $1.absences }
    }

    /// The cap that one or more further absences would bring. Nil when no further cap exists.
    public static func nextCap(absences: Int, policy: GradePolicy) -> AttendanceCap? {
        policy.attendanceCap.filter { $0.absences > absences }.min { $0.absences < $1.absences }
    }

    /// Absences left before the next cap applies. Nil when no further cap exists.
    public static func absencesUntilNextCap(absences: Int, policy: GradePolicy) -> Int? {
        nextCap(absences: absences, policy: policy).map { $0.absences - absences }
    }

    /// Letter grade from an absolute score and published cutoffs, lowered to the attendance cap.
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
    /// How many scores it will have: the set count, or one for a single score such as an exam.
    var count: Int? { expectedCount ?? (aggregation == .single ? 1 : nil) }
}
