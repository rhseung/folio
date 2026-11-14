import Foundation

public enum ReadingLimit {
    public static let pages = 30
    public static let titles = 400
    public static let pageText = 40_000
    public static let images = 8
    public static let transcript = 20_000
    // Claude는 이보다 큰 그림을 이 크기 정도로 줄이므로, 더 크게 보내면 업로드 비용만 든다.
    public static let imageEdge = 1568

    public static func clamp(_ asked: ClosedRange<Int>?, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let first = max(asked?.lowerBound ?? 1, 1), last = min(asked?.upperBound ?? count, count)
        return first <= last ? first...last : nil
    }

    public static func served(_ asked: ClosedRange<Int>, most: Int, lengths: [Int] = [], budget: Int = .max) -> ClosedRange<Int> {
        let capped = min(asked.count, max(most, 1))
        var taken = 0, used = 0
        while taken < capped {
            let length = taken < lengths.count ? lengths[taken] : 0
            if taken > 0, used + length > budget { break }
            used += length
            taken += 1
        }
        return asked.lowerBound...(asked.lowerBound + taken - 1)
    }

    public static func next(after served: ClosedRange<Int>, asked: ClosedRange<Int>, most: Int) -> ClosedRange<Int>? {
        guard served.upperBound < asked.upperBound else { return nil }
        let first = served.upperBound + 1
        return first...min(asked.upperBound, first + max(most, 1) - 1)
    }
}
