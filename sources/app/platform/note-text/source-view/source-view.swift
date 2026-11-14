import FolioDomain
import FolioMarkdown
import SwiftUI

func pastedNoteLink(_ pasted: String?, into text: String, at caret: Int, name: (AppLink) -> String?) -> String? {
    guard let pasted = pasted?.trimmingCharacters(in: .whitespacesAndNewlines), let link = AppLink(string: pasted),
        WikiLink.pastesAsLink(in: text as NSString, at: caret)
    else { return nil }
    return link.noteLink(named: name(link))
}

#if os(macOS)
extension MarkdownEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let view = SourceTextView()
        view.delegate = view
        view.onChange = { [weak coordinator = context.coordinator] in coordinator?.changed() }
        context.coordinator.view = view
        let scroll = NoteScrollView(document: view)
        view.load(text)
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? SourceTextView else { return }
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
    }
}
#else
extension MarkdownEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> SourceTextView {
        let view = SourceTextView()
        view.onChange = { [weak coordinator = context.coordinator] in coordinator?.changed() }
        context.coordinator.view = view
        view.load(text)
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
        return view
    }

    func updateUIView(_ view: SourceTextView, context: Context) {
        update(
            view, context.coordinator, accent: context.environment.accent, dark: context.environment.colorScheme == .dark,
            openLink: context.environment.openLink)
    }
}
#endif

extension NSTextLayoutManager {
    func top(of index: Int) -> CGFloat? {
        guard let location = location(documentRange.location, offsetBy: index) else { return nil }
        ensureLayout(for: NSTextRange(location: documentRange.location, end: location) ?? documentRange)
        return textLayoutFragment(for: location)?.layoutFragmentFrame.minY
    }
}
