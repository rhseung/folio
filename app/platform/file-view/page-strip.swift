import FolioDomain
import SwiftUI

/// A PDF's pages small, down the side of its file view. Pressing one goes to it. On a course's lecture file, each
/// class's pages stand beside the thumbnails as a bracket with the class's day, and a range picked on them (⇧-click on
/// a Mac, a long press then a tap on iPad) is saved as one class's progress (#147).
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

    /// Every row is this tall, so a page's place in the column is known without laying the rows out: the brackets and
    /// the band are drawn from it while the rows themselves are made only as they scroll in.
    static let row: CGFloat = 108
    static let column: CGFloat = 128
    static let lane: CGFloat = 20

    var body: some View {
        let lanes = model.lanes
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    if lanes > 0 {
                        BracketLanes(brackets: model.brackets, lanes: lanes, course: model.courseId)
                            .frame(width: CGFloat(lanes) * Self.lane, height: CGFloat(controller.pageCount) * Self.row, alignment: .topLeading)
                            .padding(.leading, Theme.Space.xs)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(1..<controller.pageCount + 1, id: \.self) { page in row(page).id(page) }
                    }
                    .background(alignment: .top) { band }
                    .frame(width: Self.column)
                }
                .padding(.vertical, Theme.Space.s)
            }
            .overflowFade(.vertical)
            .onChange(of: controller.page, initial: true) { _, page in proxy.scrollTo(page + 1) }
        }
        .overlay(alignment: .bottom) { takeBar }
        .animation(.snappy(duration: 0.2), value: model.selection)
        .frame(width: Self.column + (lanes > 0 ? CGFloat(lanes) * Self.lane + Theme.Space.xs : 0))
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: model.selection)
        #endif
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.strip) { _, step in
            switch step {
            case .range(let from, let to)?:
                model.press(from)
                model.extend(to: to)
                controller.go(to: to - 1)
            case .choose?: model.choose()
            case .save?: model.commit()
            case nil: break
            }
        }
        #endif
    }

    private func row(_ page: Int) -> some View {
        PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page)
            .padding(.horizontal, Theme.Space.m)
            .frame(height: Self.row)
            .contentShape(.rect)
            #if os(macOS)
            .gesture(TapGesture().modifiers(.shift).onEnded { pick(page, extend: true) }
                .exclusively(before: TapGesture().onEnded { pick(page, extend: false) }))
            #else
            .onTapGesture { pick(page, extend: false) }
            .onLongPressGesture { model.start(at: page) }
            #endif
            .pointingHand()
            .help(model.picks ? Text(.fileViewProgressPickHelp) : Text(verbatim: ""))
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

    @ViewBuilder private var band: some View {
        if let picked = model.selection {
            RoundedRectangle(cornerRadius: Theme.Radius.control)
                .fill(accent.color.opacity(Theme.Opacity.onTint))
                .frame(height: CGFloat(picked.count) * Self.row)
                .padding(.horizontal, Theme.Space.xs)
                .offset(y: CGFloat(picked.lowerBound - 1) * Self.row)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var takeBar: some View {
        if let label = model.selectionLabel {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xs) {
                    Text(label).font(Theme.Typeface.label).monospacedDigit().foregroundStyle(accent.ink)
                    Spacer(minLength: 0)
                    Button { model.clear() } label: { Image(systemName: "xmark").font(Theme.Glyph.small) }
                        .buttonStyle(.ghostIcon)
                        .help(Text(.fileViewProgressClear))
                }
                #if os(iOS)
                Text(.fileViewProgressWiden).font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                #endif
                Button { model.choose() } label: { Text(.fileViewProgressTake).frame(maxWidth: .infinity) }
                    .buttonStyle(.pointing(.borderedProminent))
                    .popover(isPresented: $model.choosing, arrowEdge: .top) { ProgressClassPicker(model: model) }
            }
            .padding(Theme.Space.s)
            .floatingGlass()
            .padding(Theme.Space.s)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

/// Each class's pages as a bracket with its day along it. The lanes run outward from the thumbnails, lane 0 nearest.
private struct BracketLanes: View {
    let brackets: [PageStripModel.Bracket]
    let lanes: Int
    let course: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(brackets) { bracket in
                // Inset at both ends, so two classes one after the other in a lane read as two brackets.
                BracketMark(bracket: bracket, course: course)
                    .frame(width: PageStrip.lane, height: CGFloat(bracket.pages.count) * PageStrip.row - Theme.Space.s)
                    .offset(x: CGFloat(lanes - 1 - bracket.lane) * PageStrip.lane,
                            y: CGFloat(bracket.pages.lowerBound - 1) * PageStrip.row + Theme.Space.xs)
            }
        }
    }
}

private struct BracketMark: View {
    let bracket: PageStripModel.Bracket
    let course: UUID?
    @Environment(\.openLink) private var openLink
    @Environment(\.accent) private var accent
    @State private var hovering = false

    /// The day's column and the bracket's, which together fill a lane.
    private static let text: CGFloat = 14
    private static let mark: CGFloat = 6

    var body: some View {
        Button {
            openLink(bracket.link, course: course)
        } label: {
            HStack(spacing: 0) {
                // Turned to run up along the bracket from its first page, where the eye starts reading the range.
                VStack(spacing: 0) {
                    Turned {
                        Text(bracket.day)
                            .font(Theme.Typeface.label)
                            .foregroundStyle(hovering ? accent.ink : Theme.Palette.textSecondary)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Theme.Space.s)
                .frame(width: Self.text)
                Bracket()
                    .stroke(hovering ? accent.color : Theme.Palette.textTertiary, lineWidth: 2)
                    .frame(width: Self.mark)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .onHover { hovering = $0 }
        .help(Text(.fileViewProgressOpenClass(bracket.day, PageStripModel.label(bracket.pages))))
    }
}

/// Lays out one view turned a quarter: `rotationEffect` turns only the drawing, so the view would still take its
/// unturned width, wider than a lane, and its height from the bracket.
private struct Turned: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let size = subviews.first?.sizeThatFits(.unspecified) else { return .zero }
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        view.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(view.sizeThatFits(.unspecified)))
    }
}

/// `[`: down the left, with short ends pointing at the pages.
private struct Bracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        return path
    }
}

/// Which class the picked pages were, today's or the last one before it picked first. Saving is `material link`
/// with the range, as the link popover's page bar saves it.
private struct ProgressClassPicker: View {
    @Bindable var model: PageStripModel
    @Environment(\.accent) private var accent

    var body: some View {
        let choices = model.choices
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.fileViewProgressWhichClass).font(Theme.Typeface.sectionTitle)
                if let label = model.selectionLabel {
                    Text(label).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            if choices.isEmpty {
                EmptyLine(String(localized: .fileViewProgressNoClasses))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(choices) { choice in row(choice) }
                    }
                }
                .frame(maxHeight: 280)
                .fixedSize(horizontal: false, vertical: true)
                .overflowFade(.vertical)
            }
            if let note = model.refusal ?? model.replaces {
                Text(note).font(Theme.Typeface.caption).foregroundStyle(model.refusal == nil ? Theme.Palette.textTertiary : Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(String(localized: .commonCancel)) { model.choosing = false }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(String(localized: .commonSave)) { model.commit() }
                    .buttonStyle(.pointing(.borderedProminent))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSave)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 280)
    }

    private func row(_ choice: PageStripModel.Choice) -> some View {
        let picked = model.chosen == choice.id
        return Button { model.chosen = choice.id } label: {
            HStack(spacing: Theme.Space.s) {
                Text(choice.title).lineLimit(1).foregroundStyle(picked ? accent.ink : Theme.Palette.text)
                Spacer(minLength: Theme.Space.s)
                if let pages = choice.pages {
                    Text(pages).font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(Theme.Inset.listRow)
            .background(picked ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }
}

/// One page small, with its number under it; outlined while the PDF is on it.
struct PageThumbnail: View {
    let thumbnails: PageThumbnails
    let page: Int
    let current: Bool
    @State private var image: CGImage?

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
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(current ? Theme.Palette.text : Theme.Palette.lineSoft, lineWidth: current ? 2 : 1))
            Text("\(page)").font(Theme.Typeface.label.weight(.regular)).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.vertical, Theme.Space.xxs)
        .task(id: page) { image = await thumbnails.image(page) }
    }
}
