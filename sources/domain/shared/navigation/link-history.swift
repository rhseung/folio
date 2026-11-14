import Foundation

public struct LinkHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var back: [Place] = []
    public private(set) var current: Place
    public private(set) var forward: [Place] = []
    public let limit: Int

    public init(_ current: Place, limit: Int = 100) {
        self.current = current
        self.limit = max(1, limit)
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func visit(_ place: Place) {
        guard place != current else { return }
        back.append(current)
        if back.count > limit { back.removeFirst(back.count - limit) }
        forward = []
        current = place
    }

    public mutating func replace(_ place: Place) {
        current = place
    }

    @discardableResult
    public mutating func goBack(_ steps: Int = 1) -> Bool {
        guard steps >= 1, steps <= back.count else { return false }
        for _ in 0..<steps {
            forward.insert(current, at: 0)
            current = back.removeLast()
        }
        return true
    }

    @discardableResult
    public mutating func goForward(_ steps: Int = 1) -> Bool {
        guard steps >= 1, steps <= forward.count else { return false }
        for _ in 0..<steps {
            back.append(current)
            current = forward.removeFirst()
        }
        return true
    }
}

extension LinkHistory: Codable where Place: Codable {}
