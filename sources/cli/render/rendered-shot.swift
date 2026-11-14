import FolioDomain
import Foundation

struct RenderedShot: Codable, Sendable {
    var theme: String
    var width: Int
    var height: Int
    var png: String
}
