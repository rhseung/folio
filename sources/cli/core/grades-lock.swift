import ArgumentParser
import FolioDomain
import Foundation
import LocalAuthentication

enum GradesLock {
    static let stamp = URL.cachesDirectory.appending(path: "Folio/grades-unlocked")

    static var isUnlocked: Bool {
        if let o = CLI.overrides { return o.gradesUnlocked }
        if let until = try? stamp.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, CLI.now < until {
            return true
        }
        return !hasPasscode
    }

    static var hasPasscode: Bool {
        if CLI.overrides != nil { return true }
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func masked(_ value: String) -> String { isUnlocked ? value : "••".styled(.dim) }

    static func require() throws {
        guard !isUnlocked else { return }
        try authenticate()
        unlock(for: GradeLock.unlockSeconds)
    }

    static func authenticate() throws {
        final class Result: @unchecked Sendable { var ok = false }
        let result = Result(), done = DispatchSemaphore(value: 0)
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

    static func seconds(_ text: String) -> Double? {
        let parts = text.matches(of: /(\d+)([hms])/)
        guard !parts.isEmpty, parts.map { String($0.output.0) }.joined() == text else { return nil }
        return parts.reduce(0) { sum, m in sum + Double(m.output.1)! * ["h": 3600, "m": 60, "s": 1][String(m.output.2)]! }
    }
}
