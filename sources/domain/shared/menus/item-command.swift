import Foundation

public protocol ItemCommand: Hashable, Sendable {
    var group: MenuGroup { get }
}
