import FolioDomain
import SwiftUI

@MainActor protocol ItemMenuSource {
    associatedtype Command: ItemCommand
    var commands: [Command] { get }
    func row(_ command: Command) -> MenuRow
}
