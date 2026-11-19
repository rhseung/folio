import Foundation

// 비대칭 정규분포(Azzalini)이다. `shape`가 0이면 정규분포이다. 시험 통계로 받는 평균, 중앙값, 표준편차 세 값으로
// 분포를 정하는 데 쓴다.
public struct SkewNormal: Sendable, Equatable {
    public var location: Double
    public var scale: Double
    public var shape: Double

    public init(location: Double, scale: Double, shape: Double) {
        self.location = location
        self.scale = scale
        self.shape = shape
    }

    public static let standard = SkewNormal(location: 0, scale: 1, shape: 0)

    // shape가 커지면 분포는 반정규분포로 다가가고 왜도는 약 0.995에 닿는다. 20에서 왜도가 0.985라 그 한계와 1% 안쪽이고,
    // 더 키우면 곡선의 한쪽 끝이 절벽이 되어 Newton 반복이 흔들린다.
    public static let shapeLimit = 20.0

    public var delta: Double { shape / (1 + shape * shape).squareRoot() }
    private static let b = (2 / Double.pi).squareRoot()

    public var mean: Double { location + scale * Self.b * delta }
    public var stdDev: Double { scale * (1 - Self.b * Self.b * delta * delta).squareRoot() }
    public var skewness: Double {
        let m = Self.b * delta
        return (4 - .pi) / 2 * m * m * m / pow(1 - m * m, 1.5)
    }
    public var median: Double { quantile(0.5) }

    // 같은 모양을 평균 0, 표준편차 1로 옮긴다.
    public var standardized: SkewNormal {
        let m = Self.b * delta, s = (1 - m * m).squareRoot()
        return SkewNormal(location: -m / s, scale: 1 / s, shape: shape)
    }

    public static func standardized(delta: Double) -> SkewNormal {
        let d = min(max(delta, -0.999_999), 0.999_999)
        let shape = min(max(d / (1 - d * d).squareRoot(), -shapeLimit), shapeLimit)
        return SkewNormal(location: 0, scale: 1, shape: shape).standardized
    }

    public func pdf(_ x: Double) -> Double {
        let z = (x - location) / scale
        return 2 / scale * Self.phi(z) * Self.normalCDF(shape * z)
    }

    public func cdf(_ x: Double) -> Double {
        let z = (x - location) / scale
        guard shape != 0 else { return Self.normalCDF(z) }
        return min(max(Self.normalCDF(z) - 2 * Self.owenT(z, shape), 0), 1)
    }

    // 꼬리에서 cdf가 0이나 1로 뭉개지므로 p를 1e-15 안쪽으로 자른다. 정규분포에서 약 ±7.9σ이다.
    public func quantile(_ p: Double) -> Double {
        let p = min(max(p, 1e-15), 1 - 1e-15)
        var lo = -40.0, hi = 40.0
        var z = Self.b * delta
        for _ in 0..<200 {
            let x = location + scale * z
            let f = cdf(x) - p
            if f > 0 { hi = z } else { lo = z }
            let density = pdf(x) * scale
            var next = density > 1e-300 ? z - f / density : .nan
            if !(next > lo && next < hi) { next = (lo + hi) / 2 }
            if abs(next - z) < 1e-13 || hi - lo < 1e-13 { z = next; break }
            z = next
        }
        return location + scale * z
    }

    // 세 값에 맞춘 분포이다. 중앙값과 표준편차는 늘 그대로 맞춘다. 평균과 중앙값의 차이가 표준편차에 비해 커서 어떤 shape로도
    // 맞지 않으면 shape를 `shapeLimit`에서 자르고 평균만 가장 가까운 값이 된다. 그래서 중앙값 이상인 점수는 늘 위로 50% 안이다.
    public static func fit(mean: Double, median: Double, stdDev: Double) -> SkewNormal {
        let target = (mean - median) / stdDev
        if target == 0 { return SkewNormal(location: median, scale: stdDev, shape: 0) }
        func gap(_ shape: Double) -> Double {
            let z = SkewNormal(location: 0, scale: 1, shape: shape)
            return (z.mean - z.median) / z.stdDev
        }
        var shape: Double
        if abs(target) >= gap(shapeLimit) {
            shape = target > 0 ? shapeLimit : -shapeLimit
        } else {
            var lo = target > 0 ? 0 : -shapeLimit, hi = target > 0 ? shapeLimit : 0
            for _ in 0..<60 {
                let mid = (lo + hi) / 2
                if gap(mid) < target { lo = mid } else { hi = mid }
            }
            shape = (lo + hi) / 2
        }
        let z = SkewNormal(location: 0, scale: 1, shape: shape).standardized
        let scale = stdDev / z.stdDev
        return SkewNormal(location: median - scale * (z.median - z.location), scale: scale * z.scale, shape: z.shape)
    }

    static func phi(_ z: Double) -> Double { exp(-z * z / 2) / (2 * Double.pi).squareRoot() }
    static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.squareRoot()) }

    // Owen의 T 함수 T(h, a) = 1/(2π) ∫₀^a exp(-h²(1+x²)/2) / (1+x²) dx이다. a > 1이면 적분 구간이 길어 정밀도가 떨어지므로
    // T(h, a) + T(ah, 1/a) = Φ(h)/2 + Φ(ah)/2 - Φ(h)Φ(ah) (h ≥ 0)로 [0, 1] 구간의 적분으로 바꾼다. T는 h에 대해 짝함수이다.
    static func owenT(_ h: Double, _ a: Double) -> Double {
        if a == 0 { return 0 }
        if a < 0 { return -owenT(h, -a) }
        let h = abs(h)
        if a > 1 {
            let p = normalCDF(h), q = normalCDF(a * h)
            return p / 2 + q / 2 - p * q - owenT(a * h, 1 / a)
        }
        let n = 64
        let step = a / Double(n)
        let f = { (x: Double) in exp(-h * h * (1 + x * x) / 2) / (1 + x * x) }
        var sum = f(0) + f(a)
        for i in 1..<n { sum += (i % 2 == 0 ? 2 : 4) * f(Double(i) * step) }
        return sum * step / 3 / (2 * Double.pi)
    }
}
