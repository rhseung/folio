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
    // 소문제들이 함께 딸린 지문이다. 문제지에서 뽑은 묶음에만 있다.
    public var groups: [ProblemGroup]

    public init(
        id: UUID = UUID(), device: DeviceID, at date: Date, title: String, source: ProblemSource = .exercise, materialId: UUID? = nil,
        solutionMaterialId: UUID? = nil, problems: [Problem] = [], groups: [ProblemGroup] = []
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
        self.groups = groups
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        updatedBy = try c.decode(DeviceID.self, forKey: .updatedBy)
        title = try c.decode(String.self, forKey: .title)
        source = try c.decode(ProblemSource.self, forKey: .source)
        materialId = try c.decodeIfPresent(UUID.self, forKey: .materialId)
        solutionMaterialId = try c.decodeIfPresent(UUID.self, forKey: .solutionMaterialId)
        problems = try c.decode([Problem].self, forKey: .problems)
        groups = try c.decodeIfPresent([ProblemGroup].self, forKey: .groups) ?? []
    }

    // 지문이 없는 묶음에 빈 `groups`를 쓰지 않는다. 지문이 생기기 전의 묶음이 저장할 때마다 바뀌지 않게 하려는 것이다.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(updatedBy, forKey: .updatedBy)
        try c.encode(title, forKey: .title)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(materialId, forKey: .materialId)
        try c.encodeIfPresent(solutionMaterialId, forKey: .solutionMaterialId)
        try c.encode(problems, forKey: .problems)
        if !groups.isEmpty { try c.encode(groups, forKey: .groups) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, updatedBy, title, source, materialId, solutionMaterialId, problems, groups
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
