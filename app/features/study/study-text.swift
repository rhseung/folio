import FolioMarkdown
import SwiftUI

// 카드와 문제의 글은 마크다운이다. 줄 단위 문법만 읽어 줄바꿈과 공백을 그대로 둔다. `$…$`와 `$$…$$`는 노트 미리보기와 같은 KaTeX 그림으로 글 사이에 넣는다.
// 그림이 아직 없으면 원문을 보이고, 수식마다 그림을 한 번 받아 둔다.
struct StudyText: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    @State private var pictures: [String: NoteMath.Picture] = [:]

    var body: some View {
        if MathSpans.hasMath(text) {
            withMath.background(MathHost()).task(id: [text, "\(scheme)"]) { await draw() }
        } else {
            Self.markdown(text)
        }
    }

    private var withMath: Text {
        MathSpans.split(text).reduce(Text(verbatim: "")) { line, span in Text("\(line)\(piece(span))") }
    }

    static func markdown(_ text: String) -> Text {
        Text(
            (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text))
    }

    private func piece(_ span: MathSpans.Span) -> Text {
        switch span {
        case .text(let text): return Self.markdown(text)
        case .inline(let formula): return math(formula, display: false) ?? Text(verbatim: "$\(formula)$")
        case .display(let formula): return math(formula, display: true).map { Text("\n\($0)\n") } ?? Text(verbatim: "$$\(formula)$$")
        }
    }

    private static func key(_ formula: String, display: Bool) -> String { "\(display)|\(formula)" }

    private func draw() async {
        let dark = scheme == .dark
        for span in MathSpans.split(text) {
            let (formula, display): (String, Bool)
            switch span {
            case .text: continue
            case .inline(let f): (formula, display) = (f, false)
            case .display(let f): (formula, display) = (f, true)
            }
            let picture = await NoteMath.shared.drawn(
                formula, syntax: .latex, display: display, size: Theme.Typeface.bodySize, dark: dark, trim: true)
            guard !Task.isCancelled else { return }
            pictures[Self.key(formula, display: display)] = picture
        }
    }

    // 그림의 가운데를 글자의 x-height 높이에 맞춘다. 글자 크기의 0.35배는 SF 글꼴에서 기준선부터 소문자 가운데까지의 높이다.
    // `Text` 안의 그림은 크기를 바꿀 수 없어서, 그림의 배율로 점 크기를 수식의 크기에 맞춘다.
    private func math(_ formula: String, display: Bool) -> Text? {
        let size = Theme.Typeface.bodySize
        guard let picture = pictures[Self.key(formula, display: display)], let cg = Self.cgImage(picture.image), picture.size.width > 0
        else { return nil }
        let image = Image(cg, scale: CGFloat(cg.width) / picture.size.width, orientation: .up, label: Text(verbatim: formula))
        return Text(image).baselineOffset(size * 0.35 - picture.size.height / 2)
    }

    private static func cgImage(_ image: PlatformImage) -> CGImage? {
        #if os(macOS)
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        image.cgImage
        #endif
    }
}
