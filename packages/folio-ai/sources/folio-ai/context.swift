import FolioDomain
import Foundation

public struct ContextItem: Sendable, Equatable, Identifiable {
    public enum Tier: Int, Sendable, Comparable {
        // Order from docs/SPEC.md "맥락 구성"; later tiers are dropped first when over budget.
        case courseSummary, userRules, focus, related, search
        public static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var title: String
    public var tier: Tier
    public var text: String
    /// JPEG images that go with the text, such as the photos a note embeds.
    public var images: [Image]

    public struct Image: Sendable, Equatable {
        public var name: String
        public var data: Data
        public init(name: String, data: Data) { self.name = name; self.data = data }
    }

    public init(id: String, title: String, tier: Tier, text: String, images: [Image] = []) {
        self.id = id
        self.title = title
        self.tier = tier
        self.text = text
        self.images = images
    }
}

public struct BuiltContext: Sendable, Equatable {
    /// System blocks; the stable part (course summary, rules) carries the cache breakpoint.
    public var system: [ContentBlock]
    public var userBlocks: [ContentBlock]
    public var included: [ContextItem]
    public var dropped: [ContextItem]
}

public enum ContextBuilder {
    /// ≈ 3 characters per token for mixed Korean/English; a 1568px image ≈ 2,500 tokens.
    public static func estimate(_ item: ContextItem) -> Int {
        item.text.count / 3 + item.images.count * 2_500
    }

    public static func build(_ items: [ContextItem], budgetTokens: Int) -> BuiltContext {
        let ordered = items.enumerated().sorted { ($0.element.tier, $0.offset) < ($1.element.tier, $1.offset) }.map(\.element)
        var included: [ContextItem] = []
        var dropped: [ContextItem] = []
        var used = 0
        for item in ordered {
            let cost = estimate(item)
            if used + cost <= budgetTokens || item.tier <= .userRules {
                included.append(item)
                used += cost
            } else {
                dropped.append(item)
            }
        }

        let stable = included.filter { $0.tier <= .userRules }
        let stableText = stable.map { "<\($0.title)>\n\($0.text)\n</\($0.title)>" }.joined(separator: "\n\n")
        var userBlocks: [ContentBlock] = []
        for item in included where item.tier > .userRules {
            userBlocks.append(.text("<\(item.title)>\n\(item.text)\n</\(item.title)>"))
            // Each image is named before it, so Claude can tie it to the link in the text above.
            for image in item.images {
                userBlocks.append(.text("\(item.title)의 그림 \(image.name):"))
                userBlocks.append(.image(image.data, mediaType: "image/jpeg"))
            }
        }
        return BuiltContext(
            system: stableText.isEmpty ? [] : [.text(stableText, cache: true)],
            userBlocks: userBlocks, included: included, dropped: dropped
        )
    }

    public static func courseSummary(_ file: CourseFile, now: Date) -> ContextItem {
        var lines = ["과목: \(file.course.title)"]
        if !file.units.isEmpty {
            lines.append("단원:")
            lines += file.units.sorted { $0.order < $1.order }.map { "- \($0.title)" }
        }
        let upcoming = file.exams.filter { ($0.start ?? .distantPast) >= now }.sorted { $0.start! < $1.start! }
        if !upcoming.isEmpty {
            lines.append("다가오는 시험:")
            lines += upcoming.map { e in
                let scope = e.scopeText.isEmpty ? "" : " 범위: \(e.scopeText)"
                return "- \(e.title) \(e.start!.formatted(.iso8601.year().month().day()))\(scope)"
            }
        }
        if !file.course.memo.isEmpty { lines += ["메모:", file.course.memo] }
        // Sorted and timestamp-free so the cached prefix stays byte-identical between requests.
        return ContextItem(id: "course:\(file.course.id)", title: "과목 요약", tier: .courseSummary, text: lines.joined(separator: "\n"))
    }
}
