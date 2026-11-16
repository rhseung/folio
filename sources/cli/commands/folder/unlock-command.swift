import ArgumentParser
import FolioDomain
import Foundation
import LocalAuthentication

struct UnlockCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unlock", abstract: String(localized: .unlockAbstract), discussion: String(localized: .unlockDiscussion))
    @OptionGroup var g: GlobalOptions
    @Option(name: .customLong("for"), help: ArgumentHelp(String(localized: .unlockHelpDuration), valueName: "duration")) var duration = "5m"

    func run() throws {
        guard let seconds = GradesLock.seconds(duration), seconds > 0 else {
            throw CLIError(
                exit: .usage, message: String(localized: .unlockBadDuration(duration)), hints: [String(localized: .unlockBadDurationHint)])
        }
        let most = Int(GradeLock.maxUnlockSeconds / 3600)
        guard seconds <= GradeLock.maxUnlockSeconds else {
            throw CLIError(exit: .usage, message: String(localized: .unlockTooLong(most, duration)), hints: ["folio unlock --for \(most)h"])
        }
        if GradesLock.hasPasscode { try GradesLock.authenticate() }
        GradesLock.unlock(for: seconds)
        let until = CLI.now.addingTimeInterval(seconds)
        struct Out: Encodable { var unlocked = true, until: Date }
        if g.json { return try printJSON(Out(until: until)) }
        say(
            "✓".styled(.green) + " " + String(localized: .unlockDone) + " "
                + String(localized: .unlockUntil(until.formatted(date: .omitted, time: .shortened))).styled(.dim))
    }
}
