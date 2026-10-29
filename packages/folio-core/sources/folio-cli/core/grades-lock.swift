import ArgumentParser
import FolioDomain
import Foundation
import LocalAuthentication

/// docs/SPEC.md "성적 잠금" in the terminal. Each run is its own process, so an unlock is kept as a file's time, not in
/// memory. Like the app's lock it hides grades from someone looking at the screen; course.json stays readable.
enum GradesLock {
    /// Its modification date is when the lock comes back.
    static let stamp = URL.cachesDirectory.appending(path: "Folio/grades-unlocked")

    static var isUnlocked: Bool {
        if let o = CLI.overrides { return o.gradesUnlocked }
        if let until = try? stamp.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, CLI.now < until { return true }
        return !hasPasscode
    }

    /// With no password set there is nothing to check against; locking would only shut the owner out (as in the app).
    static var hasPasscode: Bool {
        if CLI.overrides != nil { return true }
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func masked(_ value: String) -> String { isUnlocked ? value : "••".styled(.dim) }

    /// For commands whose whole point is grades: asks for Touch ID or the Mac password when locked. The prompt is a
    /// system dialog, so it reaches the owner even when an agent runs the command.
    static func require() throws {
        guard !isUnlocked else { return }
        try authenticate()
        unlock(for: GradeLock.unlockSeconds)
    }

    static func authenticate() throws {
        final class Result: @unchecked Sendable { var ok = false }
        let result = Result(), done = DispatchSemaphore(value: 0)
        // Tests never raise a system dialog; their override stands for the owner's answer.
        if let o = CLI.overrides {
            result.ok = o.gradesUnlocked
        } else {
            LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: .lockReason)) { ok, _ in
                result.ok = ok
                done.signal()
            }
            done.wait()
        }
        guard result.ok else {
            throw CLIError(exit: .needsConfirmation, message: String(localized: .lockLocked), hints: [String(localized: .lockLockedHint)])
        }
    }

    static func unlock(for seconds: Double) {
        guard CLI.overrides == nil else { return }
        try? FileManager.default.createDirectory(at: stamp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: stamp)
        try? FileManager.default.setAttributes([.modificationDate: CLI.now.addingTimeInterval(seconds)], ofItemAtPath: stamp.path)
    }

    static func lock() { try? FileManager.default.removeItem(at: stamp) }

    /// `90s`, `30m`, `1h`, `1h30m`.
    static func seconds(_ text: String) -> Double? {
        let parts = text.matches(of: /(\d+)([hms])/)
        guard !parts.isEmpty, parts.map { String($0.output.0) }.joined() == text else { return nil }
        return parts.reduce(0) { sum, m in sum + Double(m.output.1)! * ["h": 3600, "m": 60, "s": 1][String(m.output.2)]! }
    }
}

struct UnlockCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unlock", abstract: String(localized: .unlockAbstract), discussion: String(localized: .unlockDiscussion))
    @OptionGroup var g: GlobalOptions
    @Option(name: .customLong("for"), help: ArgumentHelp(String(localized: .unlockHelpDuration), valueName: "duration")) var duration = "5m"

    func run() throws {
        guard let seconds = GradesLock.seconds(duration), seconds > 0 else {
            throw CLIError(exit: .usage, message: String(localized: .unlockBadDuration(duration)), hints: [String(localized: .unlockBadDurationHint)])
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
        say("✓".styled(.green) + " " + String(localized: .unlockDone) + " " + String(localized: .unlockUntil(until.formatted(date: .omitted, time: .shortened))).styled(.dim))
    }
}

struct LockCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "lock", abstract: String(localized: .lockAbstract), discussion: String(localized: .lockDiscussion))
    @OptionGroup var g: GlobalOptions

    func run() throws {
        GradesLock.lock()
        if g.json { return try printJSON(["unlocked": false]) }
        say("✓".styled(.green) + " " + String(localized: .lockDone))
    }
}
