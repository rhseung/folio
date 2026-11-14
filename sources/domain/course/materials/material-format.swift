import Foundation

public enum MaterialFormat: Equatable, Sendable {
    case pdf
    case markdown
    case tex
    case code(language: String)
    case text
    case image
    case audio
    case html
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
        case .tex, .code, .text: true
        case .pdf, .markdown, .image, .audio, .html, .other: false
        }
    }

    public var name: String {
        switch self {
        case .pdf: "pdf"
        case .markdown: "markdown"
        case .tex: "tex"
        case .code: "code"
        case .text: "text"
        case .image: "image"
        case .audio: "audio"
        case .html: "html"
        case .other: "other"
        }
    }

    public static func builtPDF(of path: String) -> String? {
        guard MaterialFormat(path: path) == .tex else { return nil }
        return (path as NSString).deletingPathExtension + ".pdf"
    }

    public var highlightLanguage: String? {
        switch self {
        case .tex: "latex"
        case .code(let language): language
        case .pdf, .markdown, .text, .image, .audio, .html, .other: nil
        }
    }

    public var renderer: FileRenderer {
        switch self {
        case .pdf: .pdf
        case .markdown: .markdown
        case .tex, .code, .text: .source
        case .image: .image
        case .audio: .audio
        // 파일에서 연 페이지는 앱이 아니라 읽을 문서다. Quick Look은 페이지의 스크립트를 실행하지 않고 보여 준다.
        case .html, .other: .quickLook
        }
    }

    static let byExtension: [String: MaterialFormat] = [
        "pdf": .pdf, "md": .markdown, "markdown": .markdown, "tex": .tex,
        "txt": .text, "bib": .text, "json": .text, "yaml": .text, "yml": .text, "toml": .text, "csv": .text, "tsv": .text,
        "xml": .text, "log": .text, "ini": .text, "cfg": .text,
        "png": .image, "jpg": .image, "jpeg": .image, "gif": .image, "heic": .image, "heif": .image, "webp": .image,
        "tif": .image, "tiff": .image, "bmp": .image,
        "m4a": .audio, "mp3": .audio, "wav": .audio, "aac": .audio, "aif": .audio, "aiff": .audio, "flac": .audio, "caf": .audio,
        "html": .html, "htm": .html,
    ]

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

extension Material {
    public var format: MaterialFormat? { isFolder ? nil : MaterialFormat(path: path) }
    public var isPDF: Bool { format == .pdf }
    public var isText: Bool { format?.isText ?? false }
}
