import FolioDomain
import FolioStorage
import Foundation

@Action(
    "transcript target", "목표 GPA 바꾸기. 값을 빼면 지운다", done: "목표 GPA를 바꿨습니다",
    examples: ["folio transcript target 4.0 --dry-run", "folio transcript target --dry-run"],
    phrases: ["목표 GPA", "목표 학점", "목표 평점"])
public struct TranscriptTarget {
    /// 목표 GPA. 빼면 목표를 지운다
    @Arg var gpa: Double?

    public func run(_ ctx: ActionContext) throws {
        try ctx.editTranscript { $0.targetGPA = gpa }
    }
}
