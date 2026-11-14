import ArgumentParser
import FolioDomain
import Foundation
import LocalAuthentication

struct LockCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lock", abstract: String(localized: .lockAbstract), discussion: String(localized: .lockDiscussion))
    @OptionGroup var g: GlobalOptions

    func run() throws {
        GradesLock.lock()
        if g.json { return try printJSON(["unlocked": false]) }
        say("✓".styled(.green) + " " + String(localized: .lockDone))
    }
}
