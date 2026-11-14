import Foundation

public struct CBWidget: Codable, Equatable, Sendable {
    public static let language = "cb-widget"

    public var id: UUID
    public var height: Double?

    static func render(json: String) -> String {
        guard let widget = try? JSONDecoder().decode(CBWidget.self, from: Data(json.utf8)) else {
            return "<pre class=\"invalid-block\">\(HTMLRenderer.escape(json))</pre>\n"
        }
        let height = widget.height.map { " style=\"height:\(Int($0))px\"" } ?? ""
        return "<div class=\"cb-widget\" data-widget=\"\(widget.id.uuidString)\"\(height)></div>\n"
    }
}
