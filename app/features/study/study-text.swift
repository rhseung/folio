import FolioMarkdown
import SwiftUI

// 카드와 문제의 글은 LaTeX 본문의 작은 부분집합이다(`LaTeXText`). 마크다운으로 바꾼 뒤 줄 단위 문법만 읽어 줄바꿈과 공백을 그대로 둔다. `$…$`와 `$$…$$`는 노트 미리보기와 같은 KaTeX 그림으로 글 사이에 넣는다.
// 그림이 아직 없으면 원문을 보이고, 수식마다 그림을 한 번 받아 둔다.
struct StudyText: View {
    // 문제, 보기, 풀이, 카드 면은 문제지처럼 LaTeX 글꼴로 쓴다(`typeset`). 채점 의견과 내가 친 답은 앱 글꼴로 쓰고(`prose`), 단원과
    // 묶음의 이름은 사용자가 쓴 그대로 두고 수식만 그린다(`title`). 이름의 `*`나 `_`를 마크다운으로 읽으면 이름이 바뀌어 보인다.
    enum Look {
        case typeset, prose, title
    }

    let text: String
    var look: Look = .typeset
    @Environment(\.colorScheme) private var scheme
    @State private var pictures: [String: NoteMath.Picture] = [:]

    var body: some View {
        let source = source
        if MathSpans.hasMath(source) {
            typeset(withMath(source)).background(MathHost()).task(id: [source, "\(scheme)"]) { await draw(source) }
        } else {
            typeset(plain(source))
        }
    }

    // 이름은 사용자가 쓴 글자 그대로 둔다.
    private var source: String { look == .title ? text : LaTeXText.markdown(text) }

    // 앱 글꼴은 둘러싼 뷰의 글꼴(본문, 캡션)을 그대로 따른다.
    private func typeset(_ text: Text) -> Text { look == .typeset ? text.font(Theme.Typeface.study) : text }

    private func withMath(_ source: String) -> Text {
        MathSpans.split(source).reduce(Text(verbatim: "")) { line, span in Text("\(line)\(piece(span))") }
    }

    private func plain(_ text: String) -> Text { look == .title ? Text(verbatim: text) : Self.markdown(text) }

    static func markdown(_ text: String) -> Text {
        Text(
            (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text))
    }

    private func piece(_ span: MathSpans.Span) -> Text {
        switch span {
        case .text(let text): return plain(text)
        case .inline(let formula): return math(formula, display: false) ?? Text(verbatim: "$\(formula)$")
        case .display(let formula): return math(formula, display: true).map { Text("\n\($0)\n") } ?? Text(verbatim: "$$\(formula)$$")
        }
    }

    private static func key(_ formula: String, display: Bool) -> String { "\(display)|\(formula)" }

    private var size: CGFloat { look == .typeset ? Theme.Typeface.studySize : Theme.Typeface.bodySize }

    private func draw(_ source: String) async {
        let dark = scheme == .dark
        for span in MathSpans.split(source) {
            let (formula, display): (String, Bool)
            switch span {
            case .text: continue
            case .inline(let f): (formula, display) = (f, false)
            case .display(let f): (formula, display) = (f, true)
            }
            let picture = await NoteMath.shared.drawn(formula, syntax: .latex, display: display, size: size, dark: dark, trim: true)
            guard !Task.isCancelled else { return }
            pictures[Self.key(formula, display: display)] = picture
        }
    }

    // 그림의 가운데를 수식의 축(분수 막대의 높이)에 맞춘다. 축의 높이는 글꼴마다 다르다. Computer Modern은 글자 크기의 0.25배이고,
    // SF는 0.35배에서 소문자와 가운데가 맞는다. `Text` 안의 그림은 크기를 바꿀 수 없어서, 그림의 배율로 점 크기를 수식의 크기에 맞춘다.
    private func math(_ formula: String, display: Bool) -> Text? {
        let axis = look == .typeset ? 0.25 : 0.35
        guard let picture = pictures[Self.key(formula, display: display)], let cg = Self.cgImage(picture.image), picture.size.width > 0
        else { return nil }
        let image = Image(cg, scale: CGFloat(cg.width) / picture.size.width, orientation: .up, label: Text(verbatim: formula))
        return Text(image).baselineOffset(size * axis - picture.size.height / 2)
    }

    private static func cgImage(_ image: PlatformImage) -> CGImage? {
        #if os(macOS)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        image.cgImage
        #endif
    }
}
