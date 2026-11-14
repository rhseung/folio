import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import PDFKit

struct LectureClaude {
    var off: @MainActor () -> String?
    var ask: @MainActor (URL, [FolioDomain.Unit]) async -> ClaudeFinding

    @MainActor static func of(_ workspace: Workspace, course: LoadedCourse) -> LectureClaude {
        LectureClaude(
            off: { workspace.claudeReady ? nil : String(localized: .lectureClaudeOff) },
            ask: { url, units in
                guard workspace.claudeReady else { return .failed(String(localized: .lectureClaudeOff)) }
                return await LectureReader.askClaude(url, units: units, claude: workspace.claude(for: course))
            })
    }
}
