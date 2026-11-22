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
    // 마크다운이고 수식은 LaTeX(`$...$`)다.
    public var text: String
    public var format: ProblemFormat
    public var options: [String]
    public var answer: String?
    public var unitIds: [UUID]
    public var solution: String?
    // 해설 PDF에서 이 문제의 해설이 있는 쪽이다.
    public var solutionPage: Int?
    public var lecturePages: [ProblemPage]

    public init(
        id: UUID = UUID(), number: String, parent: String? = nil, points: Double? = nil, page: Int? = nil, text: String = "",
        format: ProblemFormat = .written, options: [String] = [], answer: String? = nil, unitIds: [UUID] = [],
        solution: String? = nil, solutionPage: Int? = nil, lecturePages: [ProblemPage] = []
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

    // 채점 뒤 보기 하나에 붙일 판정이다. 고른 보기는 마지막 판정을 따른다. 정답이 없는 문제(뽑은 문제는 대개 없다)는 Claude가
    // 채점하고, 손으로 판정을 고칠 수도 있어서 정답과 비교하면 맞은 답을 틀렸다고 칠하게 된다. 부분 점수는 칠하지 않는다.
    public func mark(of option: String, picked: String, verdict: Verdict) -> Verdict? {
        if option == picked { return verdict == .partial ? nil : verdict }
        guard let key = answer, Self.normalized(key) == Self.normalized(option) else { return nil }
        return .correct
    }

    // 공백, 대소문자, 수식 구분자 `$`는 답을 바꾸지 않는다.
    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "$" }
    }
}
