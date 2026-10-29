/// `folio help <topic>`: concepts rather than commands (docs/SPEC.md "도움말").
enum Topic: String, CaseIterable {
    case refs, output, exit, safety, fzf

    static let aliases: [String: Topic] = ["가리키기": .refs, "출력": .output, "종료코드": .exit, "종료-코드": .exit, "exit-codes": .exit, "안전": .safety]

    init?(_ name: String) {
        guard let t = Topic(rawValue: name) ?? Self.aliases[name] else { return nil }
        self = t
    }

    var title: String {
        switch self {
        case .refs: String(localized: .helpTopicRefsTitle)
        case .output: String(localized: .helpTopicOutputTitle)
        case .exit: String(localized: .helpTopicExitTitle)
        case .safety: String(localized: .helpTopicSafetyTitle)
        case .fzf: "fzf"
        }
    }

    var body: [String] {
        let text = switch self {
        case .refs: String(localized: .helpTopicRefsBody)
        case .output: String(localized: .helpTopicOutputBody)
        case .exit: String(localized: .helpTopicExitBody)
        case .safety: String(localized: .helpTopicSafetyBody)
        case .fzf: String(localized: .helpTopicFzfBody)
        }
        return text.components(separatedBy: "\n")
    }

    static func overview() -> [String] {
        [String(localized: .helpTopicsTitle).styled(.bold)] + allCases.map { "  \($0.rawValue.padded(to: 8)) \($0.title)" } + ["", String(localized: .helpTopicsUsage).styled(.dim)]
    }

    func print() {
        say(title.styled(.bold))
        for line in body { say(line.hasPrefix("  folio") ? line : line.styled(line.first?.isNumber == true ? .bold : .dim)) }
    }
}
