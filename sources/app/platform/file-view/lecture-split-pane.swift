import FolioDomain
import PDFKit
import SwiftUI

struct LectureSplitPane: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    let units: [FolioDomain.Unit]
    let note: String?
    var claude: ClaudeSplitButton?
    let save: () -> Void
    let cancel: () -> Void
    @State private var strip = SplitStrip()

    var body: some View {
        HStack(spacing: 0) {
            SplitThumbnails(controller: controller, split: $split, strip: $strip, name: name)
                .frame(width: PageStrip.lectureColumn)
            Theme.Palette.lineSoft.frame(width: 1)
            PDFKitView(controller: controller)
            Theme.Palette.lineSoft.frame(width: 1)
            panel.frame(width: Self.panel)
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.splitEdit) { _, edit in
            guard let edit, split.sections.indices.contains(edit.section) else { return }
            strip.edit(split.sections[edit.section].id, in: split)
            strip.extend(to: edit.page, in: &split)
            guard let i = strip.index(in: split) else { return }
            let first = split.sections[i].firstPage, last = split.sections[i].lastPage
            Task {
                controller.go(to: last - 1)
                try? await Task.sleep(for: .seconds(0.5))
                controller.go(to: first - 1)
            }
        }
        #endif
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                Text(.fileViewSplitTitle).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
                Spacer(minLength: Theme.Space.s)
                Button(String(localized: .commonCancel), action: cancel).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(String(localized: .commonSave), action: save).buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionEditor(split: $split, units: units, page: controller.page + 1, selected: selected) { controller.go(to: $0 - 1) }
                    if let claude { claude }
                    if let note {
                        Text(note).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).fixedSize(
                            horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
            }
            .overflowFade(.vertical)
        }
        .padding(.vertical, Theme.Space.l)
    }

    private var selected: Binding<Int?> {
        Binding(
            get: { strip.index(in: split) },
            set: { i in
                if let i, split.sections.indices.contains(i) { strip.edit(split.sections[i].id, in: split) } else { strip.done() }
            })
    }

    static let panel: CGFloat = 400

    private func name(_ i: Int) -> String {
        let s = split.sections[i]
        let unit = s.unit.flatMap { u in s.isNew ? s.title : units.first { $0.id == u }?.title ?? s.title } ?? ""
        let own = unit.isEmpty ? s.title : unit
        return own.isEmpty ? String(localized: .designSectionsUnnamed) : own
    }
}

private struct SplitThumbnails: View {
    let controller: PDFController
    @Binding var split: LectureSplit
    @Binding var strip: SplitStrip
    let name: (Int) -> String

    var body: some View {
        let items = strip.items(split, name: name)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { n, item in
                        StripItemFrame(item: item) {
                            lead(item)
                            page(item)
                        }
                        .id(item.id)
                        // 쪽마다 다음 쪽 위에 놓는다. 틈의 터치 영역이 다음 쪽의 위쪽까지 내려가기 때문이다.
                        .zIndex(-Double(n))
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .overflowFade(.vertical)
            .onChange(of: controller.page) { _, page in
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(strip.itemID(showing: page + 1, in: split)) }
            }
        }
        .animation(Theme.Motion.quick, value: items)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: split.sections.map(\.pages))
        #endif
    }

    @ViewBuilder private func lead(_ item: StripItem) -> some View {
        switch item.lead {
        case .header(let section, let open)?:
            StripHeader(
                section: section, open: open, help: Text(.fileViewSplitEditHelp),
                toggle: { strip.toggle(section.id) }, edit: { strip.edit(section.id, in: split) })
        case .edit(let section)?:
            StripEditRow(
                kind: section.kind, range: section.label, confirm: String(localized: .fileViewSplitApply),
                canConfirm: strip.changed(split), cancel: { strip.cancel(&split) }, commit: { strip.done() }
            ) {
                Text(section.title).font(Theme.Typeface.bodyStrong)
                    .foregroundStyle(section.kind == .none ? Theme.Palette.textTertiary : Theme.Palette.text)
            } extra: {
                EmptyView()
            }
        case .draft?, nil:
            EmptyView()
        }
    }

    @ViewBuilder private func page(_ item: StripItem) -> some View {
        if let page = item.page {
            StripPage(
                controller: controller, page: page, picked: item.mark == .picked, box: PageStrip.box(lecture: true),
                ranging: strip.editing != nil,
                press: { page, extend in
                    if extend { strip.extend(to: page, in: &split) } else { strip.press(page) }
                },
                start: nil
            )
            .overlay(alignment: .bottom) {
                if page < split.pageCount { gap(after: page) }
            }
            .contextMenu { menu(page) }
        }
    }

    @ViewBuilder private func menu(_ page: Int) -> some View {
        let i = split.section(at: page)
        Button(String(localized: .fileViewSplitEdit), systemImage: "arrow.up.and.down") { strip.start(at: page, in: split) }
        Button(String(localized: .fileViewSplitCutHere), systemImage: "scissors") { split.split(at: page) }
            .disabled(split.sections[i].firstPage == page)
        Button(String(localized: .designSectionsMergeBefore), systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
            split.merge(after: i - 1)
        }
        .disabled(i == 0)
    }

    private func gap(after page: Int) -> some View {
        let i = split.section(at: page)
        let boundary = split.sections[i].lastPage == page
        return Gap(boundary: boundary) {
            if boundary { split.merge(after: i) } else { split.split(at: page + 1) }
        }
    }
}

private struct Gap: View {
    let boundary: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accent) private var accent

    private var touch: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            if hovering {
                Rectangle()
                    .fill(boundary ? accent.color : Theme.Palette.textTertiary)
                    .frame(height: boundary ? 2 : 1)
                    .padding(.horizontal, Theme.Space.m)
                Image(systemName: boundary ? "arrow.up.and.down.and.arrow.left.and.right" : "scissors")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(boundary ? accent.ink : Theme.Palette.textSecondary)
                    .padding(Theme.Space.xxs)
                    .background(Theme.Palette.card, in: .circle)
            } else if touch && !boundary {
                Image(systemName: "scissors")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Space.s)
        .contentShape(TouchTarget(side: boundary ? 0 : Theme.Size.touchTarget))
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointingHand()
        .help(Text(boundary ? .fileViewSplitJoinHelp : .fileViewSplitCutHelp))
    }
}

struct ClaudeSplitButton: View {
    let asking: Bool
    let retry: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: retry) {
            HStack(spacing: Theme.Space.tight) {
                if asking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkle").foregroundStyle(accent.color)
                }
                Text(.lectureClaudeRetry)
            }
        }
        .buttonStyle(.ghost)
        .disabled(asking)
        .help(Text(.lectureClaudeHelp))
    }
}
