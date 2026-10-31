import FolioAI
import FolioDomain
import FolioStorage
import SwiftUI

/// Nothing leaves the device until the user presses send (docs/SPEC.md "데이터 전송 원칙").
struct ClaudePanel: View {
    @State private var model: ClaudeModel
    @Environment(\.accent) private var accent
    @Environment(\.showSettings) private var showSettings
    let course: LoadedCourse
    let openNote: UUID?
    let insertIntoNote: (String) -> Void
    let showNote: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, openNote: UUID?, insertIntoNote: @escaping (String) -> Void, showNote: @escaping (UUID) -> Void) {
        _model = State(initialValue: ClaudeModel(workspace: workspace))
        self.course = course
        self.openNote = openNote
        self.insertIntoNote = insertIntoNote
        self.showNote = showNote
    }

    var body: some View {
        let built = model.built(course)
        VStack(spacing: 0) {
            header
            contextList(built)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.m)
            Theme.Palette.lineSoft.frame(height: 1)
            conversation
            if model.sending || model.status != nil { statusLine }
            ChatComposer(enabled: model.hasKey, sending: model.sending) { model.send($0, course: course) }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .task(id: course.id) { model.load(course) }
        .task(id: openNote) { model.loadOpenNote(openNote, course: course) }
        .confirmationDialog(model.confirming?.question ?? "", isPresented: Binding(get: { model.confirming != nil }, set: { if !$0 { model.confirming = nil } }),
                            titleVisibility: .visible, presenting: model.confirming) { pending in
            Button(.claudeProposalApply, role: .destructive) { model.apply(message: pending.message, index: pending.index, course: course, confirmed: true) }
        }
        .sheet(item: $model.cardDraft) { draft in
            CardEditorSheet(workspace: model.workspace, course: course, draft: draft, units: course.file.units) { model.status = String(localized: .claudeStatusCardMade) }
        }
    }

    var header: some View {
        HStack(spacing: Theme.Space.s) {
            SearchSelect(selection: Binding(get: { model.chatID }, set: { model.select($0) }), options: model.chatOptions)
            Spacer()
            Button { model.select(nil) } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.ghost)
                .help(Text(.claudeNewChat))
        }
        .padding(Theme.Space.m)
    }

    func contextList(_ built: BuiltContext) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Caption(String(localized: .claudeContext))
                Spacer()
                Text(model.tokens(built))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                addMenu
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xxs)
            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(built.included + built.dropped) { item in
                        contextRow(item, dropped: built.dropped.contains(item))
                    }
                }
            }
            // About six rows; past that the list scrolls instead of squeezing the conversation below it.
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            if !model.removed.isEmpty {
                Button(.claudeContextRestore) { model.removed = [] }
                    .buttonStyle(.ghost).font(Theme.Typeface.caption)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
    }

    func contextRow(_ item: ContextItem, dropped: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: Self.symbol(item.tier)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 16)
            Text(item.title).lineLimit(1).truncationMode(.middle).strikethrough(dropped)
            if !item.images.isEmpty {
                Label("\(item.images.count)", systemImage: "photo").labelStyle(.titleAndIcon)
                    .font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    .help(Text(.claudeContextImages(item.images.count)))
            }
            Spacer(minLength: Theme.Space.xs)
            Text(dropped ? String(localized: .claudeContextDropped) : ContextBuilder.estimate(item).formatted())
                .font(Theme.Typeface.caption).monospacedDigit()
                .foregroundStyle(dropped ? Theme.Palette.warning : Theme.Palette.textTertiary)
            Button { model.remove(item) } label: { Image(systemName: "xmark").font(Theme.Glyph.small.weight(.semibold)) }
                .buttonStyle(.ghost)
                .help(Text(.claudeContextRemove))
        }
        .padding(Theme.Inset.listRow)
        .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .contextMenu { Button(.claudeContextRemove, role: .destructive) { model.remove(item) } }
    }

    var addMenu: some View {
        SearchPicker(options: model.addOptions(course), pick: { model.addContext($0, course: course) }, prompt: String(localized: .claudeAddPrompt)) {
            Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary)
        }
        .help(Text(.claudeAddHelp))
    }

    @ViewBuilder var conversation: some View {
        if let chat = model.chat, !chat.messages.isEmpty {
            HTMLView(body: ClaudeModel.html(chat, partial: model.sending && model.answering == model.chatID ? model.partial : nil, cards: !course.file.units.isEmpty,
                                            describe: model.describe),
                     onAction: { model.handle($0, course: course, openNote: openNote, insertIntoNote: insertIntoNote, showNote: showNote) })
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: model.hasKey ? "sparkle" : "key")
                    .font(Theme.Glyph.large.weight(.semibold))
                    .foregroundStyle(model.hasKey ? accent.ink : Theme.Palette.textTertiary)
                Text(model.hasKey ? .claudeEmptyTitle : .claudeSetupTitle).font(Theme.Typeface.bodyStrong)
                Text(model.hasKey ? .claudeEmptyDetail : .claudeSetupDetail)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if !model.hasKey { Button(.claudeOpenSettings) { showSettings(.claude) }.padding(.top, Theme.Space.xs) }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var statusLine: some View {
        HStack(spacing: Theme.Space.s) {
            if model.sending {
                ProgressView().controlSize(.small)
                Text(model.partial == nil ? .claudeWaiting : .claudeWriting)
            } else if let status = model.status {
                Text(status)
            }
            Spacer(minLength: 0)
            if let failed = model.failed, !model.sending {
                Button(.claudeResend) { model.send(failed, course: course) }.buttonStyle(.ghost)
            }
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(model.failed == nil ? Theme.Palette.textSecondary : Theme.Palette.danger)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    static func symbol(_ tier: ContextItem.Tier) -> String {
        switch tier {
        case .courseSummary: "book.closed"
        case .userRules: "list.bullet.rectangle"
        case .focus: "doc.text"
        case .related: "paperclip"
        case .search: "magnifyingglass"
        }
    }
}

/// Keeps its own text so typing doesn't re-render the conversation.
struct ChatComposer: View {
    let enabled: Bool
    let sending: Bool
    let send: (String) -> Void
    @State private var text = ""

    var question: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // Last baseline, so longer text grows upward with the button kept by its last line. The button's center sits
        // 4.5pt above that baseline, the middle of a 13pt Hangul line; on its own image bottom the text hung 2-3pt low.
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
            TextField(String(localized: enabled ? .claudeAsk : .claudeAskDisabled), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .onSubmit(submit)
                .disabled(!enabled)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill").font(Theme.Glyph.large)
            }
            .buttonStyle(.ghost)
            .disabled(!enabled || sending || question.isEmpty)
            .help(Text(.claudeSend))
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
