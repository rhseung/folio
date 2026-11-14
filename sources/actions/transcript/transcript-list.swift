import FolioDomain
import Foundation

@Query(
    "transcript list", "모든 학기의 과목과 성적",
    discussion: "성적은 folio course set <과목> --grade로, 학점 합계와 GPA는 folio gpa로 본다.",
    examples: ["folio transcript list", "folio transcript list --json"], phrases: ["전체 성적표", "모든 성적"], grades: true)
public struct TranscriptList {
    public func read(_ ctx: ReadContext) throws -> [TranscriptRow] {
        try TranscriptRow.rows(ctx, in: (try? ctx.semesters()) ?? [])
    }
}
