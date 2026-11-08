import FolioDomain
import SwiftUI

/// A PDF's pages small, down the side of its file view. Pressing one goes to it. On a course's lecture file the pages
/// fall into sections, one per class that went through them, each under a one-line header that folds it; a range
/// picked on the plain pages (⇧-click on a Mac, a long press then taps on iPad) is saved as a class's progress from a
/// row above it, and a header pressed changes that class's range the same way (#147).
///
/// Drawn here rather than with PDFKit's `PDFThumbnailView`, which picks no more than one page on iPad and takes nothing
/// laid over or beside its pages.
struct PageStrip: View {
    let controller: PDFController
    @State private var model: PageStripModel
    @Environment(\.accent) private var accent

    init(controller: PDFController, workspace: Workspace, course: UUID?, material: UUID?) {
        self.controller = controller
        _model = State(initialValue: PageStripModel(workspace: workspace, course: course, material: material, pageCount: controller.pageCount))
    }

    static let column: CGFloat = 128
    /// A lecture file's column: wide enough for the saving row's "11/4(수) 오늘 19–21쪽" on one line, and for the
    /// gutter its sections' line runs down, under the headers' dots.
    static let lectureColumn: CGFloat = 208
    static let gutter: CGFloat = 32
    static let header: CGFloat = Theme.Size.toolbarButton - Theme.Space.xs
    static let line: CGFloat = 4
    /// From the column's leading edge to the line's middle: under the header's dot, past its chevron.
    static let lineCenter: CGFloat = Theme.Space.s + Theme.Space.m + Theme.Space.xs + Theme.Size.dot / 2

    var body: some View {
        let picks = model.picks
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.items) { item in
                        PageStripItem(item: item, model: model, controller: controller, gutter: picks)
                            .id(item.id)
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .overflowFade(.vertical)
            .onChange(of: controller.page, initial: true) { _, page in proxy.scrollTo(model.itemID(showing: page + 1)) }
        }
        .animation(.snappy(duration: 0.2), value: model.items)
        .frame(width: picks ? Self.lectureColumn : Self.column)
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: model.selection)
        #endif
        .task(id: model.fresh) {
            guard model.fresh != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { model.fresh = nil }
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.strip) { _, step in
            switch step {
            case .page(let page)?:
                model.clear()
                controller.go(to: page - 1)
            case .range(let from, let to)?:
                model.press(from)
                model.extend(to: to)
                controller.go(to: to - 1)
            case .edit(let page, let to)?:
                if let section = model.sections.first(where: { $0.pages.contains(page) }) { model.edit(section) }
                model.extend(to: to)
                controller.go(to: to - 1)
            case .choose?: model.choosing = model.onlyToday == nil
            case .save?: model.commit()
            case nil: break
            }
        }
        #endif
    }
}

/// One page of the column, with the header, edit row or draft row heading it, or a folded section's header alone.
private struct PageStripItem: View {
    let item: PageStripModel.Item
    @Bindable var model: PageStripModel
    let controller: PDFController
    let gutter: Bool
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch item.lead {
            case .header(let section, let open)?: header(section, open: open)
            case .edit(let section)?: SaveRow(model: model, editing: section)
            case .draft?: SaveRow(model: model, editing: nil)
            case nil: EmptyView()
            }
            if let page = item.page { thumbnail(page) }
        }
        .padding(.leading, Theme.Space.s)
        .padding(.trailing, Theme.Space.m)
        .background(alignment: .topLeading) { line }
    }

    /// The section's line beside this page: from just under the header's dot on its first page, down to above the
    /// last page's number. Square where it meets the next page, so the pages' pieces read as one line.
    @ViewBuilder private var line: some View {
        if case .line(let last) = item.mark {
            let first = item.lead != nil
            let round = PageStrip.line / 2
            UnevenRoundedRectangle(topLeadingRadius: first ? round : 0, bottomLeadingRadius: last ? round : 0,
                                   bottomTrailingRadius: last ? round : 0, topTrailingRadius: first ? round : 0)
                .fill(accent.color)
                .frame(width: PageStrip.line)
                .padding(.top, first ? PageStrip.header / 2 + Theme.Size.dot / 2 + Theme.Space.xs : 0)
                .padding(.bottom, last ? Theme.Space.xl : 0)
                .offset(x: PageStrip.lineCenter - PageStrip.line / 2)
        }
    }

    private func header(_ section: PageStripModel.Section, open: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Button { withAnimation(.snappy(duration: 0.2)) { model.toggle(section) } } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: Theme.Space.m, height: PageStrip.header)
                    .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(open ? .commonCollapse : .commonExpand))
            Button { model.edit(section) } label: {
                HStack(spacing: Theme.Space.tight) {
                    CourseDot(color: accent.color)
                    Text(section.day).font(Theme.Typeface.bodyStrong).fixedSize()
                        .foregroundStyle(open ? Theme.Palette.text : Theme.Palette.textSecondary)
                    Spacer(minLength: Theme.Space.xs)
                    Text(section.label).font(Theme.Typeface.caption).monospacedDigit().fixedSize().foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .help(Text(.fileViewProgressPickHelp))
        }
        .frame(height: PageStrip.header)
        .padding(.trailing, Theme.Space.xs)
        .background(model.fresh == section.id ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
        .padding(.bottom, open ? Theme.Space.s : Theme.Space.xxs)
    }

    private func thumbnail(_ page: Int) -> some View {
        let picked = item.mark == .picked
        return PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page, picked: picked)
            .padding(.leading, gutter ? PageStrip.gutter : Theme.Space.xs)
            .contentShape(.rect)
            #if os(macOS)
            .gesture(TapGesture().modifiers(.shift).onEnded { pick(page, extend: true) }
                .exclusively(before: TapGesture().onEnded { pick(page, extend: false) }))
            #else
            .onTapGesture { pick(page, extend: false) }
            .onLongPressGesture { model.start(at: page) }
            #endif
            .pointingHand()
    }

    /// A Mac picks the range's end with ⇧. A touch screen has no ⇧ to hold, so once a long press has started a range,
    /// a plain tap moves its end; without one up, a tap only goes to the page.
    private func pick(_ page: Int, extend: Bool) {
        #if os(iOS)
        let extend = extend || model.selection != nil
        #endif
        if extend { model.extend(to: page) } else { model.press(page) }
        controller.go(to: page - 1)
    }
}

/// The row a range is saved from: above a new range, which class it was; in place of a section's header, its range
/// changed. Saving is `material link`, the same action as the wrap-up's.
private struct SaveRow: View {
    @Bindable var model: PageStripModel
    let editing: PageStripModel.Section?
    @Environment(\.accent) private var accent

    var body: some View {
        let today = model.onlyToday
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.tight) {
                if editing == nil {
                    Circle().strokeBorder(accent.color, lineWidth: 2).frame(width: Theme.Size.dot, height: Theme.Size.dot)
                } else {
                    CourseDot(color: accent.color)
                }
                Group {
                    if let editing {
                        Text(editing.day).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.text)
                    } else if let today {
                        Text(today.day).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                        Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                    } else {
                        Text(.fileViewProgressNew).font(Theme.Typeface.bodyStrong).foregroundStyle(accent.ink)
                    }
                }
                .fixedSize()
                Spacer(minLength: Theme.Space.xs)
                if let label = model.selectionLabel {
                    Text(label).font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit().fixedSize().foregroundStyle(accent.ink)
                }
            }
            if editing == nil, today == nil { classMenu }
            HStack(spacing: Theme.Space.tight) {
                Button { withAnimation(.snappy(duration: 0.2)) { model.clear() } } label: {
                    Text(.commonCancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.ghost)
                Button { withAnimation(.snappy(duration: 0.2)) { model.commit() } } label: {
                    Text(.commonSave).frame(maxWidth: .infinity)
                }
                .buttonStyle(.pointing(.borderedProminent))
                .disabled(!model.canSave)
            }
            .controlSize(.small)
            if let refusal = model.refusal {
                Text(refusal).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.s)
        // Its dot under the headers' dots, past where their chevrons stand.
        .padding(.leading, PageStrip.lineCenter - Theme.Size.dot / 2 - Theme.Space.s * 2)
        .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.control))
        .padding(.bottom, Theme.Space.m)
        .transition(.opacity)
    }

    /// Opens to the trailing side, over the page rather than the thumbnails the range was picked on.
    private var classMenu: some View {
        Button { model.choosing = true } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(model.chosenChoice?.day ?? String(localized: .fileViewProgressNoClass)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pointing(.bordered))
        .controlSize(.small)
        .disabled(model.choices.isEmpty)
        .popover(isPresented: $model.choosing, arrowEdge: .trailing) { ProgressClassPicker(model: model) }
    }
}

/// Which class a new range was: the classes held so far with no pages of this file yet, today's picked first.
private struct ProgressClassPicker: View {
    @Bindable var model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.fileViewProgressPickClass).font(Theme.Typeface.sectionTitle)
                if let label = model.selectionLabel {
                    Text(label).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.top, Theme.Space.xs)
            Divider().padding(.vertical, Theme.Space.xxs)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.choices) { choice in row(choice) }
                }
            }
            .frame(maxHeight: 280)
            .fixedSize(horizontal: false, vertical: true)
            .overflowFade(.vertical)
        }
        .padding(Theme.Space.tight)
        .frame(width: 240)
    }

    private func row(_ choice: PageStripModel.Choice) -> some View {
        let picked = model.chosen == choice.id
        return Button {
            model.chosen = choice.id
            model.choosing = false
        } label: {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "checkmark").font(Theme.Glyph.small).opacity(picked ? 1 : 0)
                Text(choice.title).lineLimit(1)
                if choice.today {
                    Text(.fileViewProgressToday).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(picked ? accent.ink : Theme.Palette.text)
            .padding(Theme.Inset.listRow)
            .background(picked ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }
}

/// One page small, with its number under it; on a soft rounded wash while the PDF is on it, as Preview marks it, and
/// ringed in the course's colour while it is in a range being picked. The wash is grey, not the course's tint, so a
/// current page that is also picked still reads as both, and neither looks like the save row above a range.
struct PageThumbnail: View {
    let thumbnails: PageThumbnails
    let page: Int
    let current: Bool
    var picked = false
    @State private var image: CGImage?
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: Theme.Space.xxs) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    Theme.Palette.fill
                }
            }
            .frame(height: 84)
            .clipShape(.rect(cornerRadius: Theme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(picked ? accent.color : Theme.Palette.lineSoft, lineWidth: picked ? 2 : 1))
            Text("\(page)").font(picked || current ? Theme.Typeface.label : Theme.Typeface.label.weight(.regular)).monospacedDigit()
                .foregroundStyle(picked ? accent.ink : current ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Space.s)
        .background {
            // Sideways the wash reaches into the column's margins rather than padding the page in, so a strip of fixed
            // width keeps its pages as wide as they were. Its corner is the page's plus the reach, to run alongside it.
            if current {
                RoundedRectangle(cornerRadius: Theme.Radius.small + Theme.Space.s)
                    .fill(Theme.Palette.fill)
                    .padding(.horizontal, -Theme.Space.s)
            }
        }
        .task(id: page) { image = await thumbnails.image(page) }
    }
}
