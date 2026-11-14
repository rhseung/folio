import FolioDomain
import SwiftUI

extension PageRangeField.Section {
    static func list(_ file: CourseFile, material: UUID, pageCount: Int?) -> [Self] {
        let titles = Dictionary(file.units.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        return file.lectureZones(of: material, pageCount: pageCount).map { zone in
            Self(title: zone.units.first.flatMap { titles[$0] } ?? "", pages: zone.pages)
        }
    }
}

struct SectionStrip: View {
    let sections: [PageRangeField.Section]
    let pages: Int
    let range: ClosedRange<Int>?
    var width: CGFloat = 72

    @Environment(\.accent) private var accent

    var body: some View {
        Canvas { context, size in
            let n = CGFloat(max(pages, 1))
            func x(_ edge: Int) -> CGFloat { CGFloat(edge) / n * size.width }
            for (i, s) in sections.enumerated() where s.pages.lowerBound <= pages {
                let lo = x(s.pages.lowerBound - 1) + (i == 0 ? 0 : 0.5)
                let hi = x(min(s.pages.upperBound, pages)) - (i == sections.count - 1 ? 0 : 0.5)
                let rect = CGRect(x: lo, y: 0, width: max(hi - lo, 1), height: size.height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: Theme.Radius.mark),
                    with: .color(s.title.isEmpty ? Theme.Palette.fill : Theme.Palette.text.opacity(Theme.Opacity.toneEdge)))
            }
            if let range {
                let lo = x(range.lowerBound - 1), hi = x(min(range.upperBound, pages))
                context.fill(
                    Path(roundedRect: CGRect(x: lo, y: 0, width: max(hi - lo, 2), height: size.height), cornerRadius: Theme.Radius.mark),
                    with: .color(accent.color))
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityHidden(true)
    }

    static let height: CGFloat = 6
}

struct SectionProgress: View {
    let file: CourseFile
    let material: UUID
    let range: ClosedRange<Int>
    var labeled = true

    var body: some View {
        let sections = PageRangeField.Section.list(file, material: material, pageCount: nil)
        HStack(spacing: Theme.Space.tight) {
            SectionStrip(sections: sections, pages: max(sections.last?.pages.upperBound ?? 0, range.upperBound), range: range)
            if labeled, let label = file.sectionLabel(of: material, pages: range) {
                Text(label).lineLimit(1).truncationMode(.tail)
            }
        }
    }
}

struct SectionEditor: View {
    @Binding var split: LectureSplit
    let units: [FolioDomain.Unit]
    var page: Int?
    var selected: Binding<Int?>?
    var pick: (Int) -> Void = { _ in }

    @State private var own: Int?

    private var picked: Binding<Int?> { selected ?? $own }

    var body: some View {
        let selected = picked
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionBar(split: $split, selected: selected, label: label, page: page, pick: pick)
            VStack(spacing: 0) {
                ForEach(Array(split.sections.enumerated()), id: \.element.id) { i, section in
                    SectionRow(split: $split, id: section.id, units: units, selected: selected.wrappedValue == i, label: label(i))
                        .contentShape(.rect)
                        .onTapGesture {
                            guard let i = split.sections.firstIndex(where: { $0.id == section.id }) else { return }
                            selected.wrappedValue = i
                            pick(split.sections[i].firstPage)
                        }
                }
            }
        }
        .onChange(of: split.sections.count) { _, count in if let s = selected.wrappedValue, s >= count { selected.wrappedValue = nil } }
    }

    func label(_ i: Int) -> String {
        guard split.sections.indices.contains(i) else { return "" }
        let s = split.sections[i]
        guard let unit = s.unit else { return "" }
        if s.isNew { return s.title }
        return units.first { $0.id == unit }?.title ?? s.title
    }
}

struct SectionBar: View {
    @Binding var split: LectureSplit
    @Binding var selected: Int?
    let label: (Int) -> String
    var page: Int?
    var pick: (Int) -> Void = { _ in }

    @Environment(\.accent) private var accent
    @State private var hovered: Int?
    @State private var hoverBoundary: Int?
    @State private var dragging: Int?
    @State private var moved = false
    @State private var ticks = 0
    @State private var bumps = 0

    static let tile: CGFloat = 28
    static let bubbleRow: CGFloat = 20
    private static let gap: CGFloat = 4
    #if os(macOS)
    private static let reach: CGFloat = 6
    #else
    private static let reach: CGFloat = Theme.Size.touchTarget / 2
    #endif

    var body: some View {
        GeometryReader { proxy in bar(width: proxy.size.width) }
            .frame(height: Self.bubbleRow + Self.tile)
            .sensoryFeedback(.selection, trigger: ticks)
            .sensoryFeedback(.alignment, trigger: bumps)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
                guard let i = selected, let reach = split.boundaryRange(after: i) else { return .ignored }
                let step = (press.key == .rightArrow ? 1 : -1) * (press.modifiers.contains(.shift) ? 5 : 1)
                let was = split.sections[i].lastPage
                let target = was + step
                let landed = split.moveBoundary(after: i, to: target)
                if !reach.contains(target) { bumps += 1 } else if landed != was { ticks += 1 }
                return .handled
            }
            .help(Text(.designSectionsBarHelp))
    }

    // MARK: Geometry

    private func x(_ edge: Int, _ w: CGFloat) -> CGFloat { CGFloat(edge) / CGFloat(split.pageCount) * w }
    private func page(at px: CGFloat, _ w: CGFloat) -> Int { min(max(Int(px / w * CGFloat(split.pageCount)) + 1, 1), split.pageCount) }

    private func rect(_ i: Int, _ w: CGFloat) -> CGRect {
        let s = split.sections[i]
        let lo = x(s.firstPage - 1, w) + (i == 0 ? 0 : Self.gap / 2)
        let hi = x(s.lastPage, w) - (i == split.sections.count - 1 ? 0 : Self.gap / 2)
        return CGRect(x: lo, y: Self.bubbleRow, width: max(hi - lo, 2), height: Self.tile)
    }

    private func boundary(near px: CGFloat, _ w: CGFloat) -> Int? {
        split.sections.indices.dropLast().min { abs(x(split.sections[$0].lastPage, w) - px) < abs(x(split.sections[$1].lastPage, w) - px) }
            .flatMap { abs(x(split.sections[$0].lastPage, w) - px) <= Self.reach ? $0 : nil }
    }

    private func shape(_ i: Int) -> UnevenRoundedRectangle {
        let first = i == 0, last = i == split.sections.count - 1
        let outer = Theme.Radius.control, inner = Theme.Radius.small
        return UnevenRoundedRectangle(
            topLeadingRadius: first ? outer : inner, bottomLeadingRadius: first ? outer : inner,
            bottomTrailingRadius: last ? outer : inner, topTrailingRadius: last ? outer : inner)
    }

    // MARK: Drawing

    private func bar(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(context, width: w) }
                .allowsHitTesting(false)
            ForEach(Array(split.sections.enumerated()), id: \.element.id) { i, s in
                let r = rect(i, w)
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .overlay(alignment: .leading) { text(i, width: r.width) }
                    .contentShape(.rect)
                    .help(tip(i))
                    .position(x: r.midX, y: r.midY)
            }
            ForEach(grips, id: \.self) { b in
                Capsule()
                    .fill(dragging == b ? accent.color : Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
                    .frame(width: 4, height: 16)
                    .position(x: x(split.sections[b].lastPage, w), y: Self.bubbleRow + Self.tile / 2)
                    .allowsHitTesting(false)
            }
            if let b = dragging, split.sections.indices.contains(b + 1) {
                let bx = x(split.sections[b].lastPage, w)
                Text(.designSectionsBoundary(split.sections[b].lastPage, split.sections[b + 1].firstPage))
                    .font(Theme.Typeface.label).monospacedDigit()
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: Self.bubbleRow - 2)
                    .background(Theme.Palette.card, in: .capsule)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .fixedSize()
                    .position(x: min(max(bx, 32), w - 32), y: Self.bubbleRow / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: Self.bubbleRow + Self.tile)
        .contentShape(.rect)
        .gesture(drag(width: w))
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { v in
                if let made = split.split(at: page(at: v.location.x, w)) {
                    selected = made
                    bumps += 1
                }
            }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                hoverBoundary = dragging == nil ? boundary(near: p.x, w) : hoverBoundary
                hovered = hoverBoundary == nil ? split.section(at: page(at: p.x, w)) : nil
            case .ended:
                hoverBoundary = nil
                hovered = nil
            }
        }
        #if os(macOS)
        .pointerStyle(hoverBoundary != nil || dragging != nil ? .columnResize : nil)
        #endif
        .animation(Theme.Motion.quick, value: split.sections.map(\.pages))
    }

    private func draw(_ context: GraphicsContext, width w: CGFloat) {
        for (i, s) in split.sections.enumerated() {
            let r = rect(i, w)
            let path = shape(i).path(in: r)
            if s.unit == nil {
                context.fill(path, with: .color(Theme.Palette.fill))
                var hatch = Path()
                var hx = r.minX - r.height
                while hx < r.maxX {
                    hatch.move(to: CGPoint(x: hx, y: r.maxY))
                    hatch.addLine(to: CGPoint(x: hx + r.height, y: r.minY))
                    hx += Theme.Space.s
                }
                var clipped = context
                clipped.clip(to: path)
                clipped.stroke(hatch, with: .color(Theme.Palette.text.opacity(Theme.Opacity.hover)), lineWidth: 1)
            } else {
                let opacity =
                    selected == i
                    ? Theme.Opacity.zonePicked
                    : hovered == i
                        ? Theme.Opacity.onTint
                        : i % 2 == 0 ? Theme.Opacity.tint : Theme.Opacity.zoneAlt
                context.fill(path, with: .color(accent.color.opacity(opacity)))
            }
            if s.isNew {
                context.stroke(
                    shape(i).inset(by: 0.5).path(in: r), with: .color(accent.color.opacity(Theme.Opacity.liveEdge)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else if selected == i {
                context.stroke(
                    shape(i).inset(by: 0.5).path(in: r), with: .color(accent.color.opacity(Theme.Opacity.liveEdge)), lineWidth: 1)
            }
        }
        if let page, page >= 1, page <= split.pageCount {
            let px = x(page - 1, w) + x(1, w) / 2
            context.fill(Path(CGRect(x: px - 1, y: Self.bubbleRow + Self.tile - 4, width: 2, height: 4)), with: .color(Theme.Palette.text))
        }
    }

    @ViewBuilder private func text(_ i: Int, width: CGFloat) -> some View {
        let room = width - 2 * Theme.Space.s
        if room > 12, split.sections.indices.contains(i) {
            let s = split.sections[i]
            let name = label(i)
            let title = Text(name).font(Theme.Typeface.label).foregroundStyle(s.unit == nil ? Theme.Palette.textTertiary : accent.ink)
            let pages = Text(pagesText(s)).font(Theme.Typeface.label.weight(.regular)).foregroundStyle(Theme.Palette.textTertiary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xs) {
                    title; pages
                }.fixedSize()
                if name.isEmpty { pages.fixedSize(); Color.clear } else { title.lineLimit(1).truncationMode(.tail) }
            }
            .frame(width: room, alignment: .leading)
            .clipped()
            .padding(.horizontal, Theme.Space.s)
            .allowsHitTesting(false)
        }
    }

    private var grips: [Int] {
        var out = Set([dragging ?? hoverBoundary].compactMap(\.self))
        #if os(iOS)
        if let selected { out.formUnion([selected - 1, selected]) }
        #endif
        return out.filter { split.sections.indices.contains($0) && split.sections.indices.contains($0 + 1) }.sorted()
    }

    private func pagesText(_ s: LectureSplit.Section) -> String {
        s.firstPage == s.lastPage ? "\(s.firstPage)" : "\(s.firstPage)–\(s.lastPage)"
    }

    private func tip(_ i: Int) -> String {
        let s = split.sections[i]
        let name = label(i).isEmpty ? String(localized: .designSectionsUnnamed) : label(i)
        return "\(name) · \(String(localized: .designSectionsPages(s.firstPage, s.lastPage)))"
    }

    // MARK: Changes

    private func drag(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if dragging == nil, !moved { dragging = boundary(near: g.startLocation.x, w) }
                if abs(g.translation.width) > 2 { moved = true }
                guard let b = dragging, moved else { return }
                let target = Int((g.location.x / w * CGFloat(split.pageCount)).rounded())
                let was = split.sections[b].lastPage
                let landed = split.moveBoundary(after: b, to: target)
                if landed != was {
                    if landed != target { bumps += 1 } else { ticks += 1 }
                }
            }
            .onEnded { g in
                defer {
                    dragging = nil
                    moved = false
                }
                guard !moved else { return }
                let i = split.section(at: page(at: g.location.x, w))
                selected = i
                pick(split.sections[i].firstPage)
            }
    }
}

// 행은 자리가 아니라 구간의 id를 가진다. 합치기나 화면 닫기로 나누기가 줄어든 뒤에도 행이 한 번 더 그려지는데, 옛
// 자리를 읽은 행은 배열 끝을 넘었다. 그래서 편집마다 실행할 때 자리를 찾는다.
private struct SectionRow: View {
    @Binding var split: LectureSplit
    let id: LectureSplit.Section.ID
    let units: [FolioDomain.Unit]
    let selected: Bool
    let label: String

    @Environment(\.accent) private var accent
    @State private var cutting = false
    @State private var cutPage = ""

    private var index: Int? { split.sections.firstIndex { $0.id == id } }

    var body: some View {
        if let index {
            row(split.sections[index], at: index)
                .alert(String(localized: .designSectionsCutTitle), isPresented: $cutting) {
                    TextField(String(localized: .designSectionsCutPage), text: $cutPage)
                        #if os(iOS)
                    .keyboardType(.numberPad)
                        #endif
                    Button(String(localized: .designSectionsCutAction)) { cut() }
                    Button(String(localized: .commonCancel), role: .cancel) {}
                } message: {
                    let s = split.sections[index]
                    Text(.designSectionsCutRange(s.firstPage + 1, s.lastPage))
                }
        }
    }

    private func cut() {
        guard let index, let page = Int(cutPage.trimmingCharacters(in: .whitespaces)),
            split.sections[index].pages.contains(page)
        else { return }
        split.split(at: page)
    }

    private func row(_ section: LectureSplit.Section, at index: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            name(section).frame(maxWidth: .infinity, alignment: .leading)
            Text(section.firstPage == section.lastPage ? "\(section.firstPage)" : "\(section.firstPage)–\(section.lastPage)")
                .font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            unitMenu(section, at: index).frame(width: 152, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: 32)
        .background(selected ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
    }

    private func edit(_ change: (Int) -> Void) {
        if let index { change(index) }
    }

    @ViewBuilder private func name(_ section: LectureSplit.Section) -> some View {
        if section.isNew {
            TextField(
                String(localized: .designSectionsNamePlaceholder),
                text: Binding(get: { section.title }, set: { title in edit { split.rename($0, to: title) } })
            )
            .textFieldStyle(.plain)
        } else {
            let own = section.title.isEmpty ? label : section.title
            Text(own.isEmpty ? String(localized: .designSectionsUnnamed) : own)
                .foregroundStyle(own.isEmpty || section.unit == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func unitMenu(_ section: LectureSplit.Section, at index: Int) -> some View {
        Menu {
            if section.match != nil {
                Text(matchHelp(section))
                Divider()
            }
            Section(String(localized: .designSectionsCourseUnits)) {
                ForEach(UnitTree.outline(units), id: \.unit.id) { item in
                    Button {
                        edit { split.setUnit(item.unit.id, of: $0) }
                    } label: {
                        if section.unit == item.unit.id && !section.isNew { Image(systemName: "checkmark") }
                        Text(String(repeating: "    ", count: item.depth) + item.unit.title)
                    }
                }
            }
            Button(
                section.title.isEmpty
                    ? String(localized: .designSectionsNewUnit) : String(localized: .designSectionsNewUnitNamed(section.title))
            ) {
                edit { split.makeNew($0) }
            }
            Button(String(localized: .designSectionsNoUnit)) { edit { split.setUnit(nil, of: $0) } }
            Divider()
            Button(String(localized: .designSectionsCut)) {
                cutPage = ""
                cutting = true
            }
            .disabled(section.firstPage == section.lastPage)
            Button(String(localized: .designSectionsMergeBefore)) { edit { split.merge(after: $0 - 1) } }.disabled(index == 0)
            Button(String(localized: .designSectionsMergeAfter)) { edit { split.merge(after: $0) } }.disabled(
                index == split.sections.count - 1)
        } label: {
            HStack(spacing: Theme.Space.tight) {
                if section.match != nil { Image(systemName: "sparkle").font(Theme.Glyph.small).foregroundStyle(accent.color) }
                menuText(section).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).pointingHand()
        .help(matchHelp(section))
    }

    @ViewBuilder private func menuText(_ section: LectureSplit.Section) -> some View {
        if section.isNew {
            Text(.designSectionsNewUnitLabel).foregroundStyle(accent.ink)
        } else if let unit = section.unit {
            Text(units.first { $0.id == unit }?.title ?? "").foregroundStyle(Theme.Palette.textSecondary)
        } else {
            Text(.designSectionsSkip).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func matchHelp(_ section: LectureSplit.Section) -> String {
        switch section.match {
        case .name: String(localized: .designSectionsMatchName)
        case .claude: String(localized: .designSectionsMatchClaude)
        case nil: String(localized: .designSectionsUnitHelp)
        }
    }
}
