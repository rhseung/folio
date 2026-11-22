import FolioCore
import FolioDomain
import Foundation

public struct ProblemSheetDraft: StructuredResult, Equatable {
    public var title: String
    public var problems: [ProblemDrafts.Draft]

    public static let schema = Schema.object(["title": Schema.string, "problems": Schema.array(ProblemDrafts.draft)])
}
