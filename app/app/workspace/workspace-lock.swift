import FolioDomain
import LocalAuthentication
import SwiftUI

extension Workspace {
    /// Grades lock again this long after unlocking, so a Mac left open does not keep them on show.
    static let gradeUnlockDuration: Duration = .seconds(GradeLock.unlockSeconds)

    func unlockGrades() async {
        let context = LAContext()
        var error: NSError?
        // With no password set on the device there is nothing to check against; locking would only shut the owner out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { gradesUnlocked = true; return }
        gradesUnlocked = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: .workspaceUnlockReason))) ?? false
        guard gradesUnlocked else { return }
        gradeRelock?.cancel()
        gradeRelock = Task {
            try? await Task.sleep(for: Self.gradeUnlockDuration)
            if !Task.isCancelled { gradesUnlocked = false }
        }
    }

    func lockGrades() {
        gradeRelock?.cancel()
        gradesUnlocked = false
    }
}
