import FolioDomain
import Foundation

public enum ContextBuilder {
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
        // 캐시된 앞부분이 요청마다 바이트 단위로 같아야 하므로, 정렬하고 시각을 넣지 않는다.
        return ContextItem(id: "course:\(file.course.id)", title: "과목 요약", tier: .courseSummary, text: lines.joined(separator: "\n"))
    }
}
