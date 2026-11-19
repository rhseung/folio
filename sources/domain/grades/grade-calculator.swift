import FolioCore
import Foundation

// 점수는 모두 0에서 100 사이이고, 비율은 0에서 1 사이이다.
public enum GradeCalculator {
    public struct ComponentResult: Sendable, Equatable {
        public var componentId: UUID
        public var ratio: Double?
        public var completion: Double
        public var z: Double?
        public var zEstimated = false
        public var curve = SkewNormal.standard
        public var gap: Double?
        public var gapFromMedian = false
        public var meanGap: Double?
    }

    public struct CourseScore: Sendable, Equatable {
        public var components: [ComponentResult]
        public var secured: Double
        public var projected: Double?
        public var z: Double?
        public var zEstimated = false
        public var curve = SkewNormal.standard
        public var gap: Double?
        public var gapFromMedian = false
        public var remainingWeight: Double

        // 손으로 고친 파일은 비중 규칙(0...100)을 벗어날 수 있다. 자르지 않고 `Int`로 바꾸면 1e19 같은 비중에서 앱이 멈춘다.
        public var remainingPercent: Int { Int(rounding: remainingWeight, in: 0...(100 * Swift.max(components.count, 1))) }
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

    // `ceilings`는 성적 요소마다 점수가 아직 없는 과제가 받을 수 있는 최대 비율이다(지각 감점). 예상 점수에서 그 과제의 몫은 요소의
    // 예상 비율과 이 비율 중 작은 쪽으로 센다. 확보한 점수는 기록한 점수만 세므로 바뀌지 않는다.
    public static func score(components: [GradeComponent], entries: [ScoreEntry], ceilings: [UUID: [Double]] = [:]) -> CourseScore {
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
            let zs = counted.compactMap { e -> Placed? in
                guard let mean = e.mean, e.max > 0 else { return nil }
                let given = e.stdDev.flatMap { $0 > 0 ? $0 : nil }
                guard let sd = given ?? spread.map({ $0 * e.max }) else { return nil }
                guard let median = e.median, median != mean else { return Placed(z: (e.score - mean) / sd, estimated: given == nil) }
                // 기운 분포의 점수는 위로 몇 %인지를 같은 백분위의 정규분포 z로 바꿔, 다른 점수의 z와 함께 평균 낸다.
                let curve = SkewNormal.fit(mean: mean, median: median, stdDev: sd)
                return Placed(z: SkewNormal.standard.quantile(curve.cdf(e.score)), estimated: given == nil, delta: curve.delta)
            }
            // 중앙값이 일부 점수에만 있으면 중앙값과의 차이와 평균과의 차이를 섞지 않고 평균과의 차이만 센다. 섞으면 기준을
            // 말할 수 없어 "평균보다 위"라는 표시가 틀린다.
            let scored = counted.filter { $0.max > 0 }
            let medianGaps = scored.compactMap { e in e.median.map { (e.score - $0) / e.max } }
            let meanGaps = scored.compactMap { e in e.mean.map { (e.score - $0) / e.max } }
            let fromMedian = !medianGaps.isEmpty && scored.allSatisfy { $0.median != nil || $0.mean == nil }
            let gaps = fromMedian ? medianGaps : meanGaps
            return ComponentResult(
                componentId: component.id,
                ratio: ratio(of: own, by: component.aggregation, expected: expected),
                completion: completion,
                z: zs.isEmpty ? nil : zs.map(\.z).reduce(0, +) / Double(zs.count),
                zEstimated: zs.contains { $0.estimated },
                curve: zs.isEmpty ? .standard : .standardized(delta: zs.map(\.delta).reduce(0, +) / Double(zs.count)),
                gap: gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count),
                gapFromMedian: fromMedian,
                meanGap: meanGaps.isEmpty ? nil : meanGaps.reduce(0, +) / Double(meanGaps.count)
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
                let caps = ceilings[r.componentId] ?? []
                guard !caps.isEmpty else { return sum + w * rate }
                let counted = entries.filter { $0.componentId == r.componentId && !$0.excused }.count
                let slots = Double(Swift.max(components.first { $0.id == r.componentId }?.count ?? 0, counted + caps.count))
                let lost = caps.reduce(0) { $0 + Swift.max(0, rate - $1) } / slots
                return sum + w * (rate - lost)
            }
        }

        let withZ = results.filter { $0.z != nil }
        let zWeight = withZ.reduce(0) { $0 + weights[$1.componentId]! }
        let z = zWeight > 0 ? withZ.reduce(0) { $0 + weights[$1.componentId]! * $1.z! } / zWeight : nil
        let delta = zWeight > 0 ? withZ.reduce(0) { $0 + (weights[$1.componentId] ?? 0) * $1.curve.delta } / zWeight : 0
        let fromMedian = results.contains { $0.gap != nil } && results.allSatisfy { $0.gap == nil || $0.gapFromMedian }
        let gapOf = { (r: ComponentResult) in fromMedian ? r.gap : r.meanGap }
        let withGap = results.filter { gapOf($0) != nil }
        let gapWeight = withGap.reduce(0) { $0 + (weights[$1.componentId] ?? 0) }
        let gap = gapWeight > 0 ? withGap.reduce(0) { $0 + (weights[$1.componentId] ?? 0) * (gapOf($1) ?? 0) } / gapWeight : nil

        return CourseScore(
            components: results, secured: secured, projected: projected, z: z,
            zEstimated: withZ.contains { $0.zEstimated }, curve: delta == 0 ? .standard : .standardized(delta: delta), gap: gap,
            gapFromMedian: fromMedian, remainingWeight: remainingWeight)
    }

    public static func requiredAverage(for target: Double, given score: CourseScore) -> Double? {
        guard score.remainingWeight > 0 else { return nil }
        return (target - score.secured) / score.remainingWeight * 100
    }

    // MARK: Relative standing

    // `z`와 `cutZ`는 `curve`(반의 분포를 평균 0, 표준편차 1로 옮긴 곡선) 위의 자리이고, 평균에서 표준편차 몇 개만큼 떨어졌는지이다.
    public struct Standing: Sendable, Equatable {
        public var above: Double
        public var cutZ: Double
        public var z: Double
        public var curve: SkewNormal
        public var inTopGrade: Bool { z >= cutZ }
    }

    // 받는 `z`는 위로 몇 %인지를 정규분포의 z로 적은 값이다(`CourseScore.z`). 곡선이 기울어도 위로 몇 %인지는 그대로이고,
    // 곡선 위에서 같은 백분위의 자리로 옮긴다.
    public static func standing(z: Double, topGradeRatio ratio: Double, curve: SkewNormal = .standard) -> Standing {
        let share = Swift.min(Swift.max(ratio, 0.001), 0.999)
        let below = SkewNormal.standard.cdf(z)
        let place = curve.shape == 0 ? z : curve.quantile(below)
        return Standing(above: 1 - below, cutZ: curve.quantile(1 - share), z: place, curve: curve)
    }

    // `gap`은 모든 점수에 중앙값이 있으면 중앙값과의, 아니면 평균과의 차이이다. 중앙값 이상이면 정확히 위로 50% 안이고, 평균은 대칭 곡선에서만
    // 중앙값과 같다. A 비율이 50%이면 A 기준선은 가운데에 있고, 비율이 더 크면 가운데 아래, 더 작으면 가운데 위에 있다.
    // 그래서 가운데의 한쪽은 이것만으로 정해지고, 다른 쪽은 퍼짐이 있어야 하므로 nil이다.
    public static func inTopGrade(gap: Double, topGradeRatio ratio: Double) -> Bool? {
        if gap >= 0, ratio >= 0.5 { return true }
        if gap <= 0, ratio <= 0.5 { return false }
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

private struct Placed {
    var z: Double
    var estimated: Bool
    var delta = 0.0
}

extension GradeComponent {
    var count: Int? { expectedCount ?? (aggregation == .single ? 1 : nil) }
}
