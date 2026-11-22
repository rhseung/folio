import Foundation

// 여러 소문제가 함께 딸린 지문이다. "Warm-up Problems" 같은 머리말이나 소문제들이 함께 보는 그림이 여기 있다. 문제지는
// 폴더 같은 나무이고 지문이 폴더다. 소문제는 `Problem.parent`가, 안쪽 지문은 `parent`가 바깥 지문의 `number`다. 지문은 풀
// 문제가 아니라서 문제 목록(`ProblemSet.problems`)에 넣지 않는다. 넣으면 문제 수, 풀기 순서, 단원 준비가 모두 지문을 문제로
// 센다.
public struct ProblemGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var number: String
    // 경로와 폴더에 보일 짧은 이름이다("Warm-up"). 없으면 번호를 보인다.
    public var title: String?
    public var parent: String?
    public var page: Int?
    // LaTeX 본문 원문이고 `StudyText`가 그리는 부분집합만 쓴다. 예전에 쓴 마크다운 강조(`**`, `*`)도 그대로 읽힌다.
    public var text: String
    public var region: ProblemRegion?
    public var figures: [ProblemRegion]

    public init(
        id: UUID = UUID(), number: String, title: String? = nil, parent: String? = nil, page: Int? = nil, text: String = "",
        region: ProblemRegion? = nil, figures: [ProblemRegion] = []
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.parent = parent
        self.page = page
        self.text = text
        self.region = region
        self.figures = figures
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try c.decode(String.self, forKey: .number)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        region = try c.decodeIfPresent(ProblemRegion.self, forKey: .region)
        figures = try c.decodeIfPresent([ProblemRegion].self, forKey: .figures) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .number)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(parent, forKey: .parent)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(region, forKey: .region)
        if !figures.isEmpty { try c.encode(figures, forKey: .figures) }
    }

    private enum CodingKeys: String, CodingKey { case id, number, title, parent, page, text, region, figures }

    public var name: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? number : t
    }
}
