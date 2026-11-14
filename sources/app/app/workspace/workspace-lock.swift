import FolioDomain
import LocalAuthentication
import SwiftUI

extension Workspace {
    static let gradeUnlockDuration: Duration = .seconds(GradeLock.unlockSeconds)

    func unlockGrades() async {
        let context = LAContext()
        var error: NSError?
        // 기기에 암호가 없으면 확인할 대상이 없고, 잠그면 주인만 막힌다.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { gradesUnlocked = true; return }
        gradesUnlocked =
            (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: .workspaceUnlockReason)))
            ?? false
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
