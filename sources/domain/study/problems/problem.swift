import FolioCore
import Foundation

public struct Problem: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    // 문제지에 적힌 번호다. 소문항은 "4(a)"이고 `parent`가 "4"다.
    public var number: String
    public var parent: String?
    public var points: Double?
    // 문제지 PDF에서 이 문제가 시작하는 쪽(1부터)이다.
    public var page: Int?
    // LaTeX 본문 원문이고 `StudyText`가 그리는 부분집합만 쓴다. 예전에 쓴 마크다운 강조(`**`, `*`)도 그대로 읽힌다.
    public var text: String
    public var format: ProblemFormat
    public var options: [String]
    public var answer: String?
    public var unitIds: [UUID]
    public var solution: String?
    // 해설 PDF에서 이 문제의 해설이 있는 쪽이다.
    public var solutionPage: Int?
    public var lecturePages: [ProblemPage]
    // 문제지 PDF에서 이 문제 전체가 있는 칸과, 풀 때 봐야 하는 그림의 칸이다. 글로 옮긴 문제에는 그림이 없어서 앱이 PDF의 이
    // 칸을 잘라 보인다. 소문제들이 함께 보는 그림은 소문제가 아니라 지문(`ProblemGroup`)에 있다.
    public var region: ProblemRegion?
    public var figures: [ProblemRegion]

    public init(
        id: UUID = UUID(), number: String, parent: String? = nil, points: Double? = nil, page: Int? = nil, text: String = "",
        format: ProblemFormat = .written, options: [String] = [], answer: String? = nil, unitIds: [UUID] = [],
        solution: String? = nil, solutionPage: Int? = nil, lecturePages: [ProblemPage] = [], region: ProblemRegion? = nil,
        figures: [ProblemRegion] = []
    ) {
        self.id = id
        self.number = number
        self.parent = parent
        self.points = points
        self.page = page
        self.text = text
        self.format = format
        self.options = options
        self.answer = answer
        self.unitIds = unitIds
        self.solution = solution
        self.solutionPage = solutionPage
        self.lecturePages = lecturePages
        self.region = region
        self.figures = figures
    }

    // Claude와 사람이 쓴 파일에서 오므로 빠진 칸은 빈 값으로 읽는다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        number = try c.decode(String.self, forKey: .number)
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        points = try c.decodeIfPresent(Double.self, forKey: .points)
        page = try c.decodeIfPresent(Int.self, forKey: .page)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        format = try c.decodeIfPresent(ProblemFormat.self, forKey: .format) ?? .written
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
        answer = try c.decodeIfPresent(String.self, forKey: .answer)
        unitIds = try c.decodeIfPresent([UUID].self, forKey: .unitIds) ?? []
        solution = try c.decodeIfPresent(String.self, forKey: .solution)
        solutionPage = try c.decodeIfPresent(Int.self, forKey: .solutionPage)
        lecturePages = try c.decodeIfPresent([ProblemPage].self, forKey: .lecturePages) ?? []
        region = try c.decodeIfPresent(ProblemRegion.self, forKey: .region)
        figures = try c.decodeIfPresent([ProblemRegion].self, forKey: .figures) ?? []
    }

    // 그림이 없는 문제에 빈 `figures`를 쓰지 않는다. 그림 칸이 생기기 전에 받은 모든 문제의 course.json이 바뀌지 않게 하려는 것이다.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(number, forKey: .number)
        try c.encodeIfPresent(parent, forKey: .parent)
        try c.encodeIfPresent(points, forKey: .points)
        try c.encodeIfPresent(page, forKey: .page)
        try c.encode(text, forKey: .text)
        try c.encode(format, forKey: .format)
        try c.encode(options, forKey: .options)
        try c.encodeIfPresent(answer, forKey: .answer)
        try c.encode(unitIds, forKey: .unitIds)
        try c.encodeIfPresent(solution, forKey: .solution)
        try c.encodeIfPresent(solutionPage, forKey: .solutionPage)
        try c.encode(lecturePages, forKey: .lecturePages)
        try c.encodeIfPresent(region, forKey: .region)
        if !figures.isEmpty { try c.encode(figures, forKey: .figures) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, number, parent, points, page, text, format, options, answer, unitIds, solution, solutionPage, lecturePages, region, figures
    }

    public var hasSolution: Bool { !(solution ?? "").isEmpty || solutionPage != nil }

    public var hasKey: Bool { format.gradesByKey && !(answer ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    public static let trueFalseOptions = ["참", "거짓"]  // strings: data, 참·거짓 문제의 정답 값
}

extension Problem {
    // 정답으로 바로 채점한다. 단답이 글자로 다르면 같은 답인지 판단할 수 없어 nil을 돌려주고, 앱이 Claude에게 묻는다.
    public func keyVerdict(for answer: String) -> Verdict? {
        guard format.gradesByKey, let key = answer.isEmpty ? nil : self.answer else { return nil }
        let given = Self.normalized(answer), expected = Self.normalized(key)
        if given == expected { return .correct }
        return format == .short ? nil : .wrong
    }

    // 공백, 대소문자, 수식 구분자 `$`는 답을 바꾸지 않는다.
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "$" }
    }
}
