import Foundation

// 문제지 하나에서 뽑은 문제와 그 지문이다.
public struct ExtractedProblems: Sendable, Equatable {
    public var problems: [Problem]
    public var groups: [ProblemGroup]

    public init(problems: [Problem], groups: [ProblemGroup] = []) {
        self.problems = problems
        self.groups = groups
    }
}
