import Foundation

/// The engine the iPad builds `.tex` with: TeX Live compiled to WebAssembly (Siglum's BusyTeX), run in a web view, as
/// iPadOS can't start Tectonic the way the Mac does (#41). Which TeX it runs is read from `tex-engine.json`, the one
/// place that changes when XeLaTeX works there too.
public enum TexWebEngine: String, Codable, Sendable {
    case pdflatex
    case xelatex

    public var name: String {
        switch self {
        case .pdflatex: "pdfLaTeX"
        case .xelatex: "XeLaTeX"
        }
    }
}

extension TexLog {
    /// Reads the TeX log itself, written with `-file-line-error` so each error names its file and line
    /// (`/hw.tex:5: Undefined control sequence.`). The web engine works in a virtual folder whose root is the
    /// document's folder, so a leading `/` is dropped from those names; files of TeX Live itself keep their path.
    /// TeX ends a build that can't go on with `Emergency stop.` and a fatal note, which say nothing the error before
    /// them didn't, so they show only when nothing else did.
    public static func issues(texLog log: String) -> [TexIssue] {
        var errors: [TexIssue] = []
        var generic: [TexIssue] = []
        var warnings: [TexIssue] = []
        for raw in log.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let issue = located(line) ?? unlocated(line) {
                if isGeneric(issue.message) { generic.append(issue) } else { errors.append(issue) }
            } else if let warning = warning(line) {
                warnings.append(warning)
            }
        }
        errors = errors.uniqued()
        return (errors.isEmpty ? Array(generic.prefix(1)) : errors) + warnings.uniqued()
    }

    private static let texLiveRoot = "/texlive/"

    private static func located(_ line: String) -> TexIssue? {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, !line.hasPrefix(" ") else { return nil }
        for i in 1..<(parts.count - 1) {
            guard let n = Int(parts[i]), n > 0 else { continue }
            var file = parts[..<i].joined(separator: ":")
            // The line number is followed by a space, or a time like `12:30` in a message would read as one.
            guard parts[i + 1].hasPrefix(" "), !file.isEmpty, !file.contains(" ") || file.hasPrefix("/") || file.hasPrefix(".") else { return nil }
            if file.hasPrefix("/"), !file.hasPrefix(texLiveRoot) { file.removeFirst() }
            var message = parts[(i + 1)...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            if message.hasPrefix("! ") { message.removeFirst(2) }
            guard !message.isEmpty else { return nil }
            return TexIssue(.error, file: file, line: n, message: message)
        }
        return nil
    }

    /// An error TeX couldn't place in a file, as a runaway argument at the end of the input.
    private static func unlocated(_ line: String) -> TexIssue? {
        guard line.hasPrefix("! ") else { return nil }
        let message = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return message.isEmpty ? nil : TexIssue(.error, message: message)
    }

    private static func isGeneric(_ message: String) -> Bool {
        message.hasPrefix("Emergency stop") || message.hasPrefix("==> Fatal error occurred")
    }

    /// LaTeX and package warnings, and boxes that don't fit. The log doesn't say which file they are in without
    /// following its parentheses, so they carry the line alone, in their message.
    private static func warning(_ line: String) -> TexIssue? {
        let starts = ["LaTeX Warning:", "LaTeX Font Warning:", "Overfull \\hbox", "Overfull \\vbox"]
        let isPackage = (line.hasPrefix("Package ") || line.hasPrefix("Class ")) && line.contains(" Warning:")
        guard starts.contains(where: line.hasPrefix) || isPackage else { return nil }
        return TexIssue(.warning, message: line.trimmingCharacters(in: .whitespaces))
    }
}

/// The files a `.tex` may read besides itself, sent with it to the web engine, which sees only what it is given;
/// Tectonic on the Mac reads the document's folder directly.
public enum TexProject {
    public struct File: Equatable, Sendable {
        /// Relative to the document's folder.
        public var path: String
        public var size: Int

        public init(path: String, size: Int) {
            self.path = path
            self.size = size
        }
    }

    /// Kinds TeX reads: sources, styles, bibliographies, and the pictures pdfLaTeX can place.
    static let kinds: Set<String> = [
        "tex", "sty", "cls", "def", "cfg", "clo", "fd", "bib", "bst", "bbx", "cbx", "lbx",
        "png", "jpg", "jpeg", "pdf", "eps", "mps", "txt", "csv", "dat",
    ]
    /// Deeper folders are a code project or an archive kept beside the document, not its inputs.
    public static let depth = 3
    /// A folder of scans would otherwise go to the web view whole on every build.
    public static let budget = 64 << 20

    /// `main` is the document's own name in that folder. Each `.tex`'s built PDF is left out: it is this build's output
    /// or another document's, and TeX never reads either. Smaller files go first, so one large scan over the budget
    /// doesn't push out the styles and figures the document needs.
    public static func inputs(of main: String, among files: [File]) -> [String] {
        let built = Set(files.compactMap { MaterialFormat.builtPDF(of: $0.path)?.lowercased() })
        var room = budget
        var chosen: [String] = []
        for file in files.sorted(by: { ($0.size, $0.path) < ($1.size, $1.path) }) {
            let parts = file.path.split(separator: "/")
            let ext = (file.path as NSString).pathExtension.lowercased()
            guard file.path != main, kinds.contains(ext), parts.count <= depth,
                  !parts.contains(where: { $0.hasPrefix(".") }), !built.contains(file.path.lowercased()),
                  file.size <= room else { continue }
            room -= file.size
            chosen.append(file.path)
        }
        return chosen.sorted()
    }
}

/// What a failed iPad build adds under its errors, so a document written for the Mac's XeLaTeX isn't taken for broken.
public enum TexWebNotice: Equatable, Sendable {
    /// The iPad's engine is another TeX than the Mac's: line breaks and fonts can differ.
    case otherEngine(TexWebEngine)
    /// The document needs XeLaTeX or LuaLaTeX (fontspec, system fonts), which the iPad doesn't run.
    case needsXeTeX

    /// Only after errors: a clean build needs no note.
    public static func notices(engine: TexWebEngine, issues: [TexIssue]) -> [TexWebNotice] {
        guard engine != .xelatex, issues.contains(where: { $0.severity == .error }) else { return [] }
        let xetexOnly = ["fontspec", "unicode-math", "xetex", "luatex", "\\setmainfont", "\\setsansfont", "\\setmonofont", "polyglossia"]
        let needs = issues.contains { issue in
            let text = issue.message.lowercased()
            return xetexOnly.contains { text.contains($0.lowercased()) }
        }
        return [.otherEngine(engine)] + (needs ? [.needsXeTeX] : [])
    }
}
