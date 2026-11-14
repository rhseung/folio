import Foundation

public struct PageRange: Equatable, Sendable {
    public enum End: Sendable { case first, last }

    public var first: Int?
    public var last: Int?

    public init(first: Int? = nil, last: Int? = nil) {
        self.first = first
        self.last = last
    }

    public static func bounds(_ pages: Int?) -> ClosedRange<Int> { 1...max(pages ?? 9_999, 1) }

    public subscript(end: End) -> Int? { end == .first ? first : last }

    public var lone: End? {
        switch (first, last) {
        case (_?, nil): .first
        case (nil, _?): .last
        default: nil
        }
    }

    public static func room(at page: Int, besides taken: [ClosedRange<Int>], pages: Int?) -> ClosedRange<Int>? {
        let bounds = Self.bounds(pages)
        guard bounds.contains(page), !taken.contains(where: { $0.contains(page) }) else { return nil }
        let lo = taken.filter { $0.upperBound < page }.map { $0.upperBound + 1 }.max() ?? bounds.lowerBound
        let hi = taken.filter { $0.lowerBound > page }.map { $0.lowerBound - 1 }.min() ?? bounds.upperBound
        return max(lo, bounds.lowerBound)...min(hi, bounds.upperBound)
    }

    func room(besides taken: [ClosedRange<Int>], pages: Int?) -> ClosedRange<Int> {
        guard let anchor = first ?? last, let room = Self.room(at: anchor, besides: taken, pages: pages) else { return Self.bounds(pages) }
        return room
    }

    public func moving(_ end: End, to page: Int?, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        var bounds = room(besides: taken, pages: pages)

        if first == nil, last == nil, let page {
            let file = Self.bounds(pages)
            guard let around = Self.room(at: min(max(page, file.lowerBound), file.upperBound), besides: taken, pages: pages) else {
                return self
            }
            bounds = around
        }

        let clamp = { (p: Int) in min(max(p, bounds.lowerBound), bounds.upperBound) }
        let moved = page.map(clamp)
        switch end {
        case .first: return PageRange(first: moved, last: last.map { max(clamp($0), moved ?? $0) })
        case .last: return PageRange(first: first.map { min(clamp($0), moved ?? $0) }, last: moved)
        }
    }

    public func tapping(_ page: Int, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        switch (first, last) {
        case (nil, nil):
            return moving(.first, to: page, pages: pages, besides: taken).moving(.last, to: page, pages: pages, besides: taken)
        case let (f?, nil):
            return page >= f
                ? moving(.last, to: page, pages: pages, besides: taken)
                : PageRange(first: page, last: f).clamped(to: room(besides: taken, pages: pages))
        case let (nil, l?):
            return page <= l
                ? moving(.first, to: page, pages: pages, besides: taken)
                : PageRange(first: l, last: page).clamped(to: room(besides: taken, pages: pages))
        case let (f?, l?): return moving(abs(page - f) <= abs(page - l) ? .first : .last, to: page, pages: pages, besides: taken)
        }
    }

    public func fitted(besides taken: [ClosedRange<Int>], pages: Int?) -> PageRange {
        guard var start = first ?? last else { return self }
        while let wall = taken.first(where: { $0.contains(start) }) { start = wall.upperBound + 1 }
        guard let room = Self.room(at: start, besides: taken, pages: pages) else { return PageRange() }
        guard let end = last else { return PageRange(first: start) }
        guard end >= start else { return PageRange() }
        return PageRange(first: first == nil ? nil : start, last: min(end, room.upperBound))
    }

    private func clamped(to bounds: ClosedRange<Int>) -> PageRange {
        let clamp = { (p: Int) in min(max(p, bounds.lowerBound), bounds.upperBound) }
        return PageRange(first: first.map(clamp), last: last.map(clamp))
    }

    public func shifted(by delta: Int, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        guard let f = first, let l = last else { return self }
        let bounds = room(besides: taken, pages: pages)
        let length = min(l - f, bounds.upperBound - bounds.lowerBound)
        let start = min(max(f + delta, bounds.lowerBound), bounds.upperBound - length)
        return PageRange(first: start, last: start + length)
    }

    public func touches(_ end: End, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> Bool {
        guard let page = self[end] else { return false }
        let bounds = room(besides: taken, pages: pages)
        let other = end == .first ? last : first
        let wall = taken.contains { $0.lowerBound == page + 1 || $0.upperBound == page - 1 }
        return page == bounds.lowerBound || ((pages != nil || wall) && page == bounds.upperBound) || page == other
    }
}
