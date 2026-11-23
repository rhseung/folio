import FolioCore
import FolioDomain
import Foundation

// 문제집에 넣은 문제 하나다. `set`은 문제집의 칸 머리에 찍힌 묶음 이름이고, Claude는 이 이름과 번호로 낸 PDF에서 풀이를 찾는다.
public struct CollectionProblem: Sendable, Equatable {
    public var set: String
    public var problem: Problem
    public var stems: [ProblemGroup]

    public init(set: String, problem: Problem, stems: [ProblemGroup] = []) {
        self.set = set
        self.problem = problem
        self.stems = stems
    }
}
