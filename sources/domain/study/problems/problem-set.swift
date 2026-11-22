import FolioCore
import Foundation

// 문제지 하나다. 문제지 파일(`materialId`)이 없으면 Claude가 쓴 문제지처럼 문제의 본문이 원본이다.
public struct ProblemSet: Entity {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var updatedBy: DeviceID

    public var title: String
    public var source: ProblemSource
    public var materialId: UUID?
    public var solutionMaterialId: UUID?
    public var problems: [Problem]

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, title: String, source: ProblemSource = .exercise, materialId: UUID? = nil,
        solutionMaterialId: UUID? = nil, problems: [Problem] = []
    ) {
        self.id = id
        self.createdAt = date
        self.updatedAt = date
        self.updatedBy = device
        self.title = title
        self.source = source
        self.materialId = materialId
        self.solutionMaterialId = solutionMaterialId
        self.problems = problems
    }

    public func problem(_ id: UUID) -> Problem? { problems.first { $0.id == id } }
}

extension ProblemSet {
    // 오타로 수천 개가 생기지 않도록, 범위는 숫자만 받고 개수를 제한한다.
    public static func numbers(from text: String) -> [String] {
        var result: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            if ends.count == 2, part.split(separator: "-").count == 2, ends[0] <= ends[1], ends[1] - ends[0] < 500 {
                result += (ends[0]...ends[1]).map(String.init)
            } else if !result.contains(part) {
                result.append(part)
            }
        }
        return result.reduce(into: []) { kept, n in if !kept.contains(n) { kept.append(n) } }
    }
}
