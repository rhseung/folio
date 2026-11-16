import Foundation

public enum TexDocument {
    static let preamble = [
        "\\documentclass[11pt]{article}", "\\usepackage{kotex}", "\\usepackage{amsmath, amssymb, amsthm}", "", "\\begin{document}",
    ]

    public static func wrap(_ body: [String]) -> String {
        (preamble + body + ["\\end{document}"]).joined(separator: "\n") + "\n"
    }
}
