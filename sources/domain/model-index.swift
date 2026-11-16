import Foundation

struct ModelIndex<Doc: Sendable> {
    let ids: [ObjectIdentifier: Set<UUID>]
    let nouns: [ObjectIdentifier: String]
    let place: String
    let world: World
    let names: [UUID: String]
}
