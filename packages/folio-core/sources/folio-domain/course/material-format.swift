import Foundation

/// What a file is, judged by its extension. The app picks how to show a file from this, and the CLI refuses to write
/// text into a file that isn't text.
public enum MaterialFormat: Equatable, Sendable {
    case pdf
    case markdown
    case tex
    /// Source code; `language` is the highlighter's name for it.
    case code(language: String)
    case text
    case other

    public init(path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        if let format = Self.byExtension[ext] {
            self = format
        } else if let language = Self.languages[ext] {
            self = .code(language: language)
        } else {
            self = .other
        }
    }

    public var isText: Bool {
        switch self {
        case .markdown, .tex, .code, .text: true
        case .pdf, .other: false
        }
    }

    /// The language name the code highlighter takes, or nil for plain text.
    public var highlightLanguage: String? {
        switch self {
        case .tex: "latex"
        case .code(let language): language
        case .pdf, .markdown, .text, .other: nil
        }
    }

    static let byExtension: [String: MaterialFormat] = [
        "pdf": .pdf, "md": .markdown, "tex": .tex,
        "txt": .text, "bib": .text, "json": .text, "yaml": .text, "yml": .text, "toml": .text, "csv": .text, "tsv": .text,
        "xml": .text, "log": .text, "ini": .text, "cfg": .text,
    ]

    /// Only languages the highlighter knows; any other source file opens as plain text through `byExtension`, or not
    /// at all.
    static let languages: [String: String] = [
        "sty": "latex", "cls": "latex",
        "py": "python",
        "c": "cpp", "h": "cpp", "cc": "cpp", "cpp": "cpp", "hpp": "cpp",
        "java": "java",
        "js": "js", "jsx": "js", "mjs": "js",
        "ts": "ts", "tsx": "ts",
        "rs": "rust", "go": "go", "sql": "sql", "swift": "swift",
        "sh": "bash", "bash": "bash", "zsh": "bash",
    ]
}
