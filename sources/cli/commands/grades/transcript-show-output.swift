import FolioActions
import FolioDomain
import Foundation

extension TranscriptShow: QueryOutput {
    func say(_ shown: Shown, _ r: Resolver) throws {
        FolioCLI.say(
            shown.name.styled(.bold) + "  "
                + String(
                    localized: .transcriptShowSummary(
                        shown.totalCredits.formatted(), shown.effectiveCredits.formatted(), GPACalculator.label(shown.gpa))
                ).styled(.dim))
        TranscriptCommand.print(shown.courses, semester: false)
    }
}
