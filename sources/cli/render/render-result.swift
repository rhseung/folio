import FolioDomain
import Foundation

struct RenderResult: Codable, Sendable {
    var images: [RenderedShot]
    var console: [String]
    var problems: [String]
}
