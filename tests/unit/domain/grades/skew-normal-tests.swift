import FolioDomain
import Foundation
import PropertyBased
import Testing

// 기대값은 scipy.stats.skewnorm과 scipy.special.owens_t로 따로 셈한 값이다. 점수는 모두 지어낸 값이다.
struct SkewNormalTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) < tolerance }

    @Test func cdfMatchesOwensT() {
        // F(x) = Φ(x) - 2T(x, α)이다. T(0.7, 3) = 0.1203632, T(-1.2, 0.4) = 0.0284261이다.
        let three = SkewNormal(location: 0, scale: 1, shape: 3), small = SkewNormal(location: 0, scale: 1, shape: 0.4)
        #expect(near(three.cdf(0.7), 0.5 * erfc(-0.7 / 2.squareRoot()) - 2 * 0.120_363_171_553_89))
        #expect(near(small.cdf(-1.2), 0.5 * erfc(1.2 / 2.squareRoot()) - 2 * 0.028_426_109_068_41))
        #expect(near(three.quantile(three.cdf(0.7)), 0.7, 1e-9))
    }

    @Test func fitsMeanMedianAndStandardDeviation() {
        // 평균 50, 중앙값 48, 표준편차 12는 shape 4.5063, location 35.0946, scale 19.1356에 맞는다.
        let fit = SkewNormal.fit(mean: 50, median: 48, stdDev: 12)
        #expect(near(fit.shape, 4.506_347, 1e-4))
        #expect(near(fit.location, 35.094_584, 1e-4) && near(fit.scale, 19.135_606, 1e-4))
        #expect(near(fit.mean, 50) && near(fit.median, 48) && near(fit.stdDev, 12))
        // 62점은 정규분포에서 위로 15.87%이지만 이 분포에서는 15.97%이고, 40점은 위로 78.75%이다.
        #expect(near(1 - fit.cdf(62), 0.159_712, 1e-5))
        #expect(near(1 - fit.cdf(40), 0.787_484, 1e-5))
    }

    @Test func outOfRangeClipsToTheMostSkewedCurve() {
        // 평균과 중앙값의 차이가 표준편차의 0.2026배를 넘으면 맞는 shape가 없다. 평균 50, 중앙값 46, 표준편차 12는 0.33배이다.
        let fit = SkewNormal.fit(mean: 50, median: 46, stdDev: 12)
        #expect(fit.shape == SkewNormal.shapeLimit)
        #expect(near(fit.median, 46) && near(fit.stdDev, 12))
        #expect(near(fit.mean, 48.431_269, 1e-4))
        #expect(near(fit.skewness, 0.985_088, 1e-5))
        // 왼쪽으로 기운 분포도 같은 한계에서 자른다.
        let left = SkewNormal.fit(mean: 46, median: 50, stdDev: 12)
        #expect(left.shape == -SkewNormal.shapeLimit && near(left.median, 50) && near(left.mean, 47.568_731, 1e-4))
    }

    @Test func standingOnASkewedCurveKeepsTheShareAbove() throws {
        let component = GradeComponent(device: device, at: now, name: "중간고사", weight: 100, aggregation: .single)
        let entry = ScoreEntry(
            device: device, at: now, componentId: component.id, title: "", score: 62, max: 100, mean: 50, median: 48, stdDev: 12)
        let score = GradeCalculator.score(components: [component], entries: [entry])
        // 위로 15.97%와 같은 백분위의 정규분포 z는 0.99564이다.
        let z = try #require(score.z)
        #expect(near(z, 0.995_640, 1e-5))
        let standing = GradeCalculator.standing(z: z, topGradeRatio: 0.3, curve: score.curve)
        #expect(near(standing.above, 0.159_712, 1e-5))
        // 곡선 위의 자리는 평균에서 표준편차 몇 개만큼 떨어졌는지이므로 (62 - 50) / 12 = 1이다. A 30%의 기준선은 +0.4106이다.
        #expect(near(standing.z, 1, 1e-6))
        #expect(near(standing.cutZ, 0.410_614, 1e-5) && standing.inTopGrade)
    }

    @Test func aScoreAtTheMedianIsInTheTopHalf() {
        for (mean, median) in [(50.0, 48.0), (50, 46), (46, 50)] {
            let fit = SkewNormal.fit(mean: mean, median: median, stdDev: 12)
            #expect(near(1 - fit.cdf(median), 0.5, 1e-9))
        }
    }

    @Test func medianDecidesTheTopHalfWithoutAStandardDeviation() throws {
        let component = GradeComponent(device: device, at: now, name: "중간고사", weight: 100, aggregation: .single)
        // 평균 60보다 낮지만 중앙값 55 이상이므로 위로 50% 안이다.
        let entry = ScoreEntry(device: device, at: now, componentId: component.id, title: "", score: 57, max: 100, mean: 60, median: 55)
        let score = GradeCalculator.score(components: [component], entries: [entry])
        #expect(score.z == nil && score.gapFromMedian)
        let gap = try #require(score.gap)
        #expect(near(gap, 0.02))
        #expect(GradeCalculator.inTopGrade(gap: gap, topGradeRatio: 0.5) == true)
    }

    // 중앙값이 일부 점수에만 있으면 평균과의 차이만 센다. 퀴즈 둘은 (57 - 60) / 100과 (72 - 70) / 100의 평균인 -0.005이다.
    @Test func mixedMediansFallBackToTheMeanGap() throws {
        let quiz = GradeComponent(device: device, at: now, name: "퀴즈", weight: 50, aggregation: .mean)
        let midterm = GradeComponent(device: device, at: now, name: "중간고사", weight: 50, aggregation: .single)
        let entries = [
            ScoreEntry(device: device, at: now, componentId: quiz.id, title: "", score: 57, max: 100, mean: 60, median: 55),
            ScoreEntry(device: device, at: now, componentId: quiz.id, title: "", score: 72, max: 100, mean: 70),
            ScoreEntry(device: device, at: now, componentId: midterm.id, title: "", score: 50, max: 100, mean: 52, median: 48),
        ]
        let score = GradeCalculator.score(components: [quiz, midterm], entries: entries)
        let quizGap = try #require(score.components[0].gap), midtermGap = try #require(score.components[1].gap)
        #expect(!score.components[0].gapFromMedian && near(quizGap, -0.005))
        #expect(score.components[1].gapFromMedian && near(midtermGap, 0.02))
        // 과목 전체도 섞이므로 중간고사는 평균과의 차이 -0.02로 센다. (-0.005 - 0.02) / 2 = -0.0125이다.
        let gap = try #require(score.gap)
        #expect(!score.gapFromMedian && near(gap, -0.0125))
    }

    static let stats = zip(Gen.int(in: 0...1000), Gen.int(in: 1...300), Gen.int(in: -400...400))

    // 중앙값이 평균과 같으면 정규분포와 같다.
    @Test func medianEqualToTheMeanIsTheNormalCurve() async {
        await propertyCheck(input: Self.stats) { m, s, d in
            let mean = Double(m) / 10, sd = Double(s) / 10, score = mean + Double(d) / 100 * sd
            let fit = SkewNormal.fit(mean: mean, median: mean, stdDev: sd)
            #expect(fit == SkewNormal(location: mean, scale: sd, shape: 0))
            let component = GradeComponent(device: device, at: now, name: "", weight: 100, aggregation: .single)
            let plain = ScoreEntry(
                device: device, at: now, componentId: component.id, title: "", score: score, max: 100, mean: mean, stdDev: sd)
            var withMedian = plain
            withMedian.median = mean
            let a = GradeCalculator.score(components: [component], entries: [plain])
            let b = GradeCalculator.score(components: [component], entries: [withMedian])
            #expect(a.z == b.z && b.curve == .standard)
        }
    }

    // 곡선이 기울어도 위로 몇 %인지는 받은 z의 정규분포 백분위와 같고, 곡선 위의 자리는 백분위 순서를 지킨다.
    @Test func skewedCurvePreservesOrderAndShare() async {
        await propertyCheck(input: Gen.int(in: -990...990), Gen.int(in: -300...300), Gen.int(in: -300...300)) { d, a, b in
            let curve = SkewNormal.standardized(delta: Double(d) / 1000)
            let (low, high) = (Swift.min(a, b), Swift.max(a, b))
            let s1 = GradeCalculator.standing(z: Double(low) / 100, topGradeRatio: 0.3, curve: curve)
            let s2 = GradeCalculator.standing(z: Double(high) / 100, topGradeRatio: 0.3, curve: curve)
            let normal = GradeCalculator.standing(z: Double(low) / 100, topGradeRatio: 0.3)
            #expect(abs(s1.above - normal.above) < 1e-12 && s1.inTopGrade == normal.inTopGrade)
            #expect(s1.z <= s2.z + 1e-9)
            #expect(abs(curve.mean) < 1e-9 && abs(curve.stdDev - 1) < 1e-9)
        }
    }
}
