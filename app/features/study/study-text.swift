import SwiftUI

// 카드와 문제의 글은 마크다운이다. 줄 단위 문법만 읽어 줄바꿈과 공백을 그대로 둔다.
struct StudyText: View {
    let text: String

    var body: some View {
        Text(
            (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(text))
    }
}
