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
            LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "성적을 보려면 잠금을 해제하세요") { ok, _ in
                result.ok = ok
                done.signal()
            }
            done.wait()
        }
        guard result.ok else {
            throw CLIError(exit: .needsConfirmation, message: "성적이 잠겨 있습니다", hints: ["Touch ID나 Mac 암호로 풀어야 보입니다: folio unlock"])
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
    static let configuration = CommandConfiguration(commandName: "unlock", abstract: "성적 잠금 풀기. Touch ID나 Mac 암호로 풀고 5분 뒤(--for로 정한 시간 뒤) 다시 잠긴다", discussion: """
        성적, GPA, 점수는 잠겨 있다. gpa, transcript, score list는 잠겨 있으면 바로 묻고, 다른 명령의 성적 칸은 ••로 가린다.
        풀려 있어도 다시 묻는다. 묻지 않고 늘릴 수 있으면 에이전트가 잠금을 끝없이 미룰 수 있다.

        예시:
          folio unlock
          folio unlock --for 1h
          folio lock
        """)
    @OptionGroup var g: GlobalOptions
    @Option(name: .customLong("for"), help: ArgumentHelp("열어 둘 시간. 예: 30m, 1h, 1h30m. 최대 12h", valueName: "duration")) var duration = "5m"

    func run() throws {
        guard let seconds = GradesLock.seconds(duration), seconds > 0 else {
            throw CLIError(exit: .usage, message: "시간을 읽지 못했습니다: \(duration)", hints: ["30m, 1h, 1h30m처럼 씁니다"])
        }
        let most = Int(GradeLock.maxUnlockSeconds / 3600)
        guard seconds <= GradeLock.maxUnlockSeconds else {
            throw CLIError(exit: .usage, message: "최대 \(most)시간까지 풀 수 있습니다: \(duration)", hints: ["folio unlock --for \(most)h"])
        }
        if GradesLock.hasPasscode { try GradesLock.authenticate() }
        GradesLock.unlock(for: seconds)
        let until = CLI.now.addingTimeInterval(seconds)
        struct Out: Encodable { var unlocked = true, until: Date }
        if g.json { return try printJSON(Out(until: until)) }
        say("✓".styled(.green) + " 성적 잠금을 풀었습니다 " + "\(until.formatted(date: .omitted, time: .shortened))에 다시 잠깁니다".styled(.dim))
    }
}

struct LockCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "lock", abstract: "성적 바로 잠그기", discussion: """
        예시:
          folio lock
        """)
    @OptionGroup var g: GlobalOptions

    func run() throws {
        GradesLock.lock()
        if g.json { return try printJSON(["unlocked": false]) }
        say("✓".styled(.green) + " 성적을 잠갔습니다")
    }
}
