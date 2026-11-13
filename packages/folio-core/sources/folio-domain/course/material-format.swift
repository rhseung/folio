import Foundation

/// What a file is, judged by its extension. The app picks how to show a file from this (`renderer`), and the CLI
/// reports it and refuses to write text into a file that isn't text.
public enum MaterialFormat: Equatable, Sendable {
    case pdf
    case markdown
    case tex
    /// Source code; `language` is the highlighter's name for it.
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
        // Markdown materials stay with the read-only note reader (#179); only notes are written in Folio.
        case .tex, .code, .text: true
        case .pdf, .markdown, .image, .audio, .html, .other: false
        }
    }

    /// The name `material show` prints and its JSON carries; a code file's language goes beside it.
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

    /// The PDF a `.tex` at `path` builds to: beside it, same name. Tracking links the pair through this, `material build`
    /// writes it and the preview falls back to it, so the three can't disagree on a name like `Problems.TEX`.
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

    /// How the app shows the file. Only what the app can't draw itself goes to Quick Look.
    public var renderer: FileRenderer {
        switch self {
        case .pdf: .pdf
        case .markdown: .markdown
        case .tex, .code, .text: .source
        case .image: .image
        case .audio: .audio
        // A page from a file is a document to read, not an app: Quick Look shows it without running its scripts.
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

/// The kinds of view a file opens in. `FileView` draws one for each; the format decides which.
public enum FileRenderer: Equatable, Sendable {
    case pdf
    /// The note reader, read only.
    case markdown
    /// Highlighted text: edited in place when it is a tracked material or a note, read only otherwise.
    case source
    case image
    case audio
    /// Quick Look inside the pane; a file it can't show either gets "can't open" and a way to another app.
    case quickLook
}

extension Material {
    /// Nil for a folder, which is opened as a folder rather than shown.
    public var format: MaterialFormat? { isFolder ? nil : MaterialFormat(path: path) }
    public var isPDF: Bool { format == .pdf }
    public var isText: Bool { format?.isText ?? false }
}
