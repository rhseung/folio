import FolioDomain
import FolioMarkdown
import SwiftUI

struct MarkdownEditor {
    @Binding var text: String
    var baseURL: URL?
    var math: MathSyntax
    @Binding var insert: String?
    var saveFile: (String, Data) -> String?
    var openNote: (String) -> Void
    var onScroll: @MainActor (Int, Double) -> Void = { _, _ in }
    var assist = NoteAssist()
    var anchor: AppLink.Anchor?
    var embeds: NoteEmbedSource?
    var revision = 0
    var insertMath: Binding<CompletionItem?> = .constant(nil)
    var openGuide: @MainActor () -> Void = {}
    var views: NoteViews?

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject {
        var parent: MarkdownEditor
        weak var view: SourceTextView?
        var updating = false
        var revealed: AppLink.Anchor?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func changed() {
            guard let view, !view.hasMarkedText() else { return }
            if !updating, parent.text != view.string { parent.text = view.string }
        }
    }

    @MainActor func update(
        _ view: SourceTextView, _ coordinator: Coordinator, accent: CourseAccent, dark: Bool, openLink: OpenLinkAction = OpenLinkAction()
    ) {
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.baseURL = baseURL
        view.saveFile = saveFile
        view.openNote = openNote
        view.linkOpener = openLink
        view.linkName = embeds?.name ?? { _ in nil }
        view.onScroll = onScroll
        view.openGuide = openGuide
        if views?.editor !== view { views?.editor = view }

        view.configure(accent: accent, syntax: math, dark: dark)
        view.setAssist(assist, syntax: math)
        #if os(macOS)
        view.cards = embeds
        view.cardsRevision = revision
        #endif

        // 바인딩에는 아직 조합 중인 음절이 없다. 이때 텍스트를 바꾸면 입력기가 조합하던 음절이 지워지고, 입력기는 그다음 자모부터 빈칸을 사이에 두고 입력한다.
        if view.string != text, !view.hasMarkedText() { view.replace(with: text) }
        // 노트 텍스트가 들어오기 전에는 앵커를 찾지 않는다. 모델은 뷰를 만든 뒤에 텍스트를 읽으므로, 빈 텍스트에서 찾으면 앵커를 찾지 못하고 포기한다. 미리보기처럼 앵커가 없으면 기록을 지운다. 그래야
        // 앵커 없이 노트로 돌아왔다가 다시 앵커로 앞으로 갈 때 캐럿이 다시 움직인다.
        if anchor == nil { coordinator.revealed = nil }
        if let anchor, anchor != coordinator.revealed, !text.isEmpty, view.string == text {
            coordinator.revealed = anchor
            if let location = anchor.location(in: text) { view.reveal(location) }
        }

        afterUpdate($insert) { view.insertAtCaret($0) }
        afterUpdate(insertMath) { view.insertMath($0) }
    }

    // 바인딩 값은 갱신이 끝난 뒤에 넣는다. 갱신 중에 한 편집은 `text`에 닿지 않고(`updating`), 바인딩을 비우면서 생기는 갱신이 텍스트를 되돌리기 때문이다. 넣을 때 값을 다시 확인하므로,
    // 넣기 전에 갱신이 두 번 돌아도 한 번만 넣는다.
    @MainActor private func afterUpdate<Value>(_ binding: Binding<Value?>, _ put: @escaping @MainActor (Value) -> Void) {
        guard binding.wrappedValue != nil else { return }
        DispatchQueue.main.async {
            guard let value = binding.wrappedValue else { return }
            binding.wrappedValue = nil
            put(value)
        }
    }
}
