import Foundation

public struct CBWidget: Codable, Equatable, Sendable {
    public static let language = "cb-widget"

    public var id: UUID
    public var height: Double?

    // 애셋 서랍이 넣는 블록이다. 높이는 쓰지 않는다. 미리보기가 위젯이 알린 높이를 따르기 때문이다.
    public static func block(_ id: UUID) -> String { "```\(language)\n{\"id\": \"\(id.uuidString)\"}\n```" }

    static func render(json: String) -> String {
        guard let widget = try? JSONDecoder().decode(CBWidget.self, from: Data(json.utf8)) else {
            return "<pre class=\"invalid-block\">\(HTMLRenderer.escape(json))</pre>\n"
        }
        let height = widget.height.map { " style=\"height:\(Int($0))px\"" } ?? ""
        return "<div class=\"cb-widget\" data-widget=\"\(widget.id.uuidString)\"\(height)></div>\n"
    }
}
