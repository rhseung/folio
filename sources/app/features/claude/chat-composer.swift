import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

// 입력할 때마다 대화가 다시 그려지지 않도록 글을 자기 상태로 둔다.
struct ChatComposer: View {
    let enabled: Bool
    let sending: Bool
    let send: (String) -> Void
    let stop: () -> Void
    @State private var text = ""

    var question: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // 마지막 baseline에 맞추므로 긴 글은 위로 자라고 버튼은 마지막 줄 옆에 남는다. 버튼의 중심은 그 baseline보다
        // 4.5pt 위, 즉 13pt 한글 줄의 가운데에 있다. 이미지의 아래 끝에 맞추면 글이 2-3pt 아래로 처졌다.
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
            TextField(String(localized: enabled ? .claudeAsk : .claudeAskDisabled), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .onSubmit(submit)
                .disabled(!enabled)
            Button(action: sending ? stop : submit) {
                Image(systemName: sending ? "stop.circle.fill" : "arrow.up.circle.fill").font(Theme.Glyph.large)
            }
            .buttonStyle(.ghost)
            .disabled(!enabled || (!sending && question.isEmpty))
            .help(Text(sending ? .claudeStop : .claudeSend))
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .floatingGlass()
        .padding(Theme.Space.m)
    }

    func submit() {
        guard enabled, !sending, !question.isEmpty else { return }
        send(question)
        text = ""
    }
}
