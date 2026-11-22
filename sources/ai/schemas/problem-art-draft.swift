import FolioCore
import FolioDomain
import Foundation

public struct ProblemArtDraft: StructuredResult, Encodable, Equatable {
    public var figure: String?
    public var solutionFigure: String?
    public var solution: String?

    public init(figure: String? = nil, solutionFigure: String? = nil, solution: String? = nil) {
        self.figure = figure
        self.solutionFigure = solutionFigure
        self.solution = solution
    }

    public static let schema = Schema.object([
        "figure": Schema.nullable(Schema.string), "solutionFigure": Schema.nullable(Schema.string),
        "solution": Schema.nullable(Schema.string),
    ])
}
