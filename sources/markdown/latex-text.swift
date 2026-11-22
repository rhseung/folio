import Foundation

// 문제와 카드의 글은 LaTeX 본문의 작은 부분집합이다(문제지에서 뽑은 원문을 그대로 두기 위해서다). 화면은 이 글을 줄 단위 마크다운과
// `$…$`로 바꿔 그린다. 예전 문제는 마크다운(`**`, `*`)으로 쓰였으므로, 수식 밖의 `*`와 `_`는 그대로 두어 두 문법을 함께 읽는다.
// 읽는 것: 빈 줄 문단과 `\\` 줄바꿈, `\textbf` `\emph` `\textit` `\underline` `\texttt`, 두 단계까지의 itemize와 enumerate(`\item[(a)]`의
// 이름표 포함), `\% \& \# \_ \$ \{ \}`와 `~`, `--`, `---`, ``` `` ''' ```, 수식 `$…$` `\(…\)` `$$…$$` `\[…\]`와 equation, align, gather 환경.
// 모르는 명령은 원문 그대로 둔다.
public enum LaTeXText {
    public static func markdown(_ source: String) -> String {
        // LaTeX 명령이 하나도 없는 글은 예전 마크다운이다. 한국어 마크다운은 범위를 `1~3`으로 쓰므로, `~`와 `--`만 보고 LaTeX로 읽으면
        // 글이 바뀐다.
        // 수식 안의 명령(`$\\alpha$`)은 마크다운 글에도 있으므로 수식 밖만 본다.
        let prose = MathSpans.split(source).compactMap { span -> String? in if case .text(let t) = span { t } else { nil } }
        guard prose.contains(where: { $0.contains(/\\[A-Za-z()\[\]\\%&#_{}]/) }) else { return source }
        var reader = Reader(text: Array(source))
        return reader.read(until: nil).trimmingCharacters(in: .newlines)
    }

    static let mathEnvironments: Set<String> = ["equation", "equation*", "align", "align*", "gather", "gather*"]
    static let escapes: [Character: String] = ["%": "%", "&": "&", "#": "#", "_": "\\_", "$": "\\$", "{": "{", "}": "}"]

    private struct Reader {
        let text: [Character]
        var i = 0
        // 열린 목록마다 종류와 지금 번호다.
        var lists: [(numbered: Bool, count: Int)] = []

        init(text: [Character]) { self.text = text }

        func peek(_ s: String, at: Int? = nil) -> Bool {
            let start = at ?? i
            let chars = Array(s)
            guard start + chars.count <= text.count else { return false }
            return Array(text[start..<start + chars.count]) == chars
        }

        // `close`가 nil이면 글 끝까지, `}`이면 짝이 맞는 닫는 괄호까지 읽는다.
        mutating func read(until close: Character?) -> String {
            var out = ""
            while i < text.count {
                let c = text[i]
                if let close, c == close { return out }
                if c == "$" {
                    out += math()
                } else if c == "`", !peek("``") {
                    out += code()
                } else if c == "\\" {
                    var piece = command()
                    // 목록의 첫 항목이 줄 끝 뒤에 오면 빈 줄이 생기지 않게 한다.
                    if piece.hasPrefix("\n") {
                        while out.hasSuffix(" ") { out.removeLast() }
                        if out.hasSuffix("\n") || out.isEmpty { piece.removeFirst() }
                    }
                    out += piece
                } else if c == "{" {
                    i += 1
                    out += read(until: "}")
                    if i < text.count { i += 1 }
                } else if c == "~" {
                    out.append("\u{00A0}")
                    i += 1
                } else if peek("---") {
                    out.append("\u{2014}")
                    i += 3
                } else if peek("--") {
                    out.append("\u{2013}")
                    i += 2
                } else if peek("``") {
                    out.append("\u{201C}")
                    i += 2
                } else if peek("''") {
                    out.append("\u{201D}")
                    i += 2
                } else if c == "\n" || c == " ", !lists.isEmpty {
                    // 목록 안의 줄바꿈과 들여쓰기는 원문의 모양일 뿐이다. 항목은 `\item`이 새 줄로 연다.
                    if !out.hasSuffix(" "), !out.hasSuffix("\n") { out.append(" ") }
                    i += 1
                } else {
                    out.append(c)
                    i += 1
                }
            }
            return out
        }

        // 마크다운의 코드 조각은 글자 그대로 옮긴다. 코드의 `--`나 `~`는 기호가 아니다.
        mutating func code() -> String {
            var j = i + 1
            while j < text.count, text[j] != "`", text[j] != "\n" { j += 1 }
            guard j < text.count, text[j] == "`" else {
                i += 1
                return "`"
            }
            let s = String(text[i...j])
            i = j + 1
            return s
        }

        // `$…$`와 `$$…$$`는 닫는 곳까지 그대로 옮긴다. 수식 안의 `\`와 `_`는 KaTeX가 읽는다.
        mutating func math() -> String {
            let fence = peek("$$") ? "$$" : "$"
            var j = i + fence.count
            while j < text.count {
                if text[j] == "\\" {
                    j += 2
                    continue
                }
                if peek(fence, at: j) {
                    let s = String(text[i..<j + fence.count])
                    i = j + fence.count
                    return s
                }
                j += 1
            }
            i += fence.count
            return fence
        }

        mutating func command() -> String {
            let next = i + 1 < text.count ? text[i + 1] : nil
            guard let next else {
                i += 1
                return "\\"
            }
            if next == "\\" {
                i += 2
                return "\n"
            }
            if next == "(" || next == "[" {
                let display = next == "["
                let end = display ? "\\]" : "\\)"
                var j = i + 2
                while j < text.count, !peek(end, at: j) { j += 1 }
                guard j < text.count else { return passOne() }
                let formula = String(text[i + 2..<j]).trimmingCharacters(in: .whitespacesAndNewlines)
                i = j + 2
                return display ? "$$\(formula)$$" : "$\(formula)$"
            }
            if let escaped = LaTeXText.escapes[next] {
                i += 2
                return escaped
            }
            var j = i + 1
            while j < text.count, text[j].isLetter { j += 1 }
            let name = String(text[i + 1..<j])
            guard !name.isEmpty else { return passOne() }
            switch name {
            case "textbf", "emph", "textit", "underline", "texttt":
                guard j < text.count, text[j] == "{" else { return passOne() }
                i = j + 1
                let inner = read(until: "}")
                if i < text.count { i += 1 }
                switch name {
                case "textbf": return "**\(inner)**"
                case "emph", "textit": return "*\(inner)*"
                case "texttt": return "`\(inner)`"
                default: return inner
                }
            case "begin":
                guard let env = argument(after: j) else { return passOne() }
                if LaTeXText.mathEnvironments.contains(env.name) {
                    let end = "\\end{\(env.name)}"
                    var k = env.end
                    while k < text.count, !peek(end, at: k) { k += 1 }
                    guard k < text.count else { return passOne() }
                    let body = String(text[i..<k + end.count])
                    i = k + end.count
                    return "$$\(body)$$"
                }
                guard env.name == "itemize" || env.name == "enumerate" else { return passOne() }
                lists.append((env.name == "enumerate", 0))
                i = env.end
                skipBlank()
                return ""
            case "end":
                guard let env = argument(after: j), env.name == "itemize" || env.name == "enumerate", !lists.isEmpty else {
                    return passOne()
                }
                lists.removeLast()
                i = env.end
                guard lists.isEmpty else { return "" }
                // 목록 뒤 원문의 줄 끝은 목록을 닫는 줄바꿈과 같은 줄이다.
                while i < text.count, text[i] == " " { i += 1 }
                if i < text.count, text[i] == "\n" { i += 1 }
                return "\n"
            case "item":
                guard !lists.isEmpty else { return passOne() }
                i = j
                var label: String?
                if i < text.count, text[i] == "[" {
                    var k = i + 1
                    while k < text.count, text[k] != "]" { k += 1 }
                    label = String(text[i + 1..<min(k, text.count)])
                    i = min(k + 1, text.count)
                }
                skipBlank()
                lists[lists.count - 1].count += 1
                let list = lists[lists.count - 1]
                let mark = label ?? (list.numbered ? "\(list.count)." : "\u{2022}")
                let indent = String(repeating: "\u{2003}", count: lists.count - 1)
                return "\n\(indent)\(mark) "
            default:
                // 모르는 명령은 인자의 괄호까지 원문으로 둔다. 괄호를 묶음으로 읽어 벗기면 원문과 달라 보인다.
                i = j
                var raw = "\\" + name
                while i < text.count, text[i] == "{" || text[i] == "[" {
                    let close: Character = text[i] == "{" ? "}" : "]"
                    var k = i + 1
                    while k < text.count, text[k] != close { k += 1 }
                    guard k < text.count else { break }
                    raw += String(text[i...k])
                    i = k + 1
                }
                return raw
            }
        }

        mutating func skipBlank() { while i < text.count, text[i] == " " || text[i] == "\n" { i += 1 } }

        // 읽지 못한 명령은 `\`만 넘기고 나머지를 글로 읽는다.
        mutating func passOne() -> String {
            i += 1
            return "\\"
        }

        func argument(after j: Int) -> (name: String, end: Int)? {
            guard j < text.count, text[j] == "{" else { return nil }
            var k = j + 1
            while k < text.count, text[k] != "}" { k += 1 }
            guard k < text.count else { return nil }
            return (String(text[j + 1..<k]), k + 1)
        }
    }
}
