import Foundation

// 과제 종류 하나다. 접두어가 과제 폴더 이름의 앞부분(`HW03`)이고, 별칭은 파일 이름에서 이 종류로 읽는 낱말이다. 종류 표는
// `settings.json`의 `assignmentKinds`로 바꿀 수 있고, 비어 있으면 `builtIn`이다. 자료 추측, 정리 계획, 빠른 추가, 과제 폴더 이름이
// 모두 같은 표를 읽는다(`Settings.assignmentKindTable`).
public struct AssignmentKind: Codable, Sendable, Hashable {
    public var prefix: String
    public var aliases: [String]

    public init(prefix: String, aliases: [String] = []) {
        self.prefix = prefix
        self.aliases = aliases
    }

    // 종류는 폴더 이름으로 가리키므로, 설정에서 별칭을 더한 `Lab`도 기본 표의 `Lab`과 같은 종류다.
    public static func == (a: Self, b: Self) -> Bool { a.prefix == b.prefix }
    public func hash(into hasher: inout Hasher) { hasher.combine(prefix) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prefix = try c.decode(String.self, forKey: .prefix)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

extension AssignmentKind {
    public static let homework = AssignmentKind(prefix: "HW", aliases: ["homework", "assignment", "assign", "pa", "과제", "숙제"])
    public static let lab = AssignmentKind(prefix: "Lab")
    public static let report = AssignmentKind(prefix: "Report")
    public static let project = AssignmentKind(prefix: "Project")
    public static let slowProblem = AssignmentKind(prefix: "SP", aliases: ["slow problem", "slow problems"])
    public static let reading = AssignmentKind(prefix: "Reading")

    // 앞에 있는 종류가 먼저다. 두 종류가 같은 별칭을 가지면 앞의 종류로 읽는다.
    public static let builtIn = [homework, lab, report, project, slowProblem, reading]

    public var words: [String] { [prefix.lowercased()] + aliases.map { $0.lowercased() } }

    // 접두어는 폴더 이름의 앞부분이라 영문자만 쓴다(`StandardLayout.assignmentFolder`).
    public var isValid: Bool { !prefix.isEmpty && prefix.allSatisfy { $0.isASCII && $0.isLetter } }

    // 파일 이름에서 종류 낱말과 번호를 읽는다(`gt_hw_2`, `Lab 2 report`). 앞에 영문자가 붙은 낱말은 읽지 않는다.
    static func mentioned(in name: String, kinds: [AssignmentKind]) -> FileRule.Match? {
        let words = kinds.flatMap(\.words)
        guard !words.isEmpty,
            let regex = try? Regex(#"(?i)(?:^|[^a-z])(("# + FileRule.alternation(words) + #")[\s_-]*(\d{1,2}))(?!\d)"#),
            let m = name.firstMatch(of: regex), let text = m.output[1].substring, let word = m.output[2].substring,
            let digits = m.output[3].substring, let number = Int(digits), let kind = kind(of: String(word), kinds: kinds)
        else { return nil }
        return FileRule.Match(words: String(text), number: number, assignment: kind)
    }

    static func kind(of word: String, kinds: [AssignmentKind]) -> AssignmentKind? {
        kinds.first { kind in
            (try? Regex("(?i)" + FileRule.alternation(kind.words))).map { word.wholeMatch(of: $0) != nil } ?? false
        }
    }
}
