import FolioDomain
import SwiftUI

/// A choice shown as a rounded chip with ⌃⌄, opening a menu. Replaces the stock pop-up button.
struct ChoiceMenu<Value: Hashable>: View {
    struct Option: Hashable {
        let value: Value
        let label: String
    }

    @Binding var selection: Value
    let options: [Option]

    init(selection: Binding<Value>, options: [(Value, String)]) {
        self._selection = selection
        self.options = options.map { Option(value: $0.0, label: $0.1) }
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            ChipLabel(options.first { $0.value == selection }?.label ?? "")
        }
        .menuStyle(.button)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }
}

/// The ⌃⌄ chip that ChoiceMenu and the search pickers open from.
struct ChipLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Theme.Space.tight) {
            // Its own width up to 240, then truncated: a long title must not widen the row it sits in.
            Text(text).lineLimit(1).frame(maxWidth: 240, alignment: .leading).fixedSize()
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Glyph.small)
                .foregroundStyle(Theme.Palette.textTertiary)
        }
        .chip()
    }
}

struct PickOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var detail: String?
    /// Consecutive options with the same section get one heading.
    var section: String?
    var depth = 0
    /// Can't be picked, only unpicked; `detail` should say why.
    var disabled = false
}

/// A chip that opens a popover with a search field over the options; ↑↓ move, return picks, esc closes.
/// For lists that grow with the user's data (codes, people, units, files). Fixed short enums stay on ChoiceMenu.
struct SearchPicker<ID: Hashable, Label: View>: View {
    let options: [PickOption<ID>]
    var isSelected: (ID) -> Bool = { _ in false }
    let pick: (ID) -> Void
    /// Multiple choice keeps the popover open after a pick.
    var multiple = false
    var prompt = String(localized: .commonSearch)
    /// For a label that should shrink and truncate with its row instead of holding its full width.
    var flexible = false
    /// Offered when the query names no option, so one row both picks and makes (a class's units, #403).
    var create: ((String) -> Void)?
    var createTitle: (String) -> String = { $0 }
    @ViewBuilder let label: Label
    @State private var open = false
    @State private var query = ""
    @State private var highlighted: ID?
    @FocusState private var focused: Bool

    var filtered: [PickOption<ID>] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { o in [o.title, o.detail, o.section].contains { $0?.localizedCaseInsensitiveContains(q) == true } }
    }

    /// The query, when it can be made: no option already has that title.
    var creatable: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard create != nil, !q.isEmpty, !options.contains(where: { $0.title.caseInsensitiveCompare(q) == .orderedSame }) else { return nil }
        return q
    }

    var body: some View {
        Button { open.toggle() } label: { label }
            .buttonStyle(.pointing(.plain))
            .fixedSize(horizontal: !flexible, vertical: true)
            .popover(isPresented: $open, arrowEdge: .bottom) { panel }
    }

    var panel: some View {
        let rows = filtered
        return VStack(spacing: 0) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if let id = highlighted ?? rows.first?.id { choose(id) } else if let title = creatable { make(title) }
                    }
                    .onKeyPress(.downArrow) { step(1, in: rows); return .handled }
                    .onKeyPress(.upArrow) { step(-1, in: rows); return .handled }
            }
            .padding(Theme.Space.m)
            Theme.Palette.line.frame(height: 1)
            if let title = creatable {
                createRow(title)
                if !rows.isEmpty { Theme.Palette.lineSoft.frame(height: 1) }
            }
            if rows.isEmpty {
                if creatable == nil {
                    EmptyLine(String(localized: .designNoMatch)).padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, o in
                                if let section = o.section, i == 0 || rows[i - 1].section != section {
                                    Caption(section).padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xxs)
                                }
                                row(o).id(o.id)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                    .overflowFade(.vertical)
                    .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 340)
        .font(Theme.Typeface.body)
        .onAppear {
            query = ""
            highlighted = options.first { isSelected($0.id) }?.id
            focused = true
        }
        .onChange(of: query) { highlighted = filtered.first?.id }
    }

    func row(_ o: PickOption<ID>) -> some View {
        Button { choose(o.id) } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "checkmark").font(Theme.Glyph.regular)
                    .opacity(isSelected(o.id) ? 1 : 0)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(o.title).lineLimit(1)
                    if let detail = o.detail { Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Space.m + CGFloat(o.depth) * Theme.Space.m)
            .padding(.trailing, Theme.Space.m)
            .padding(.vertical, Theme.Space.tight)
            .background(highlighted == o.id ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .padding(.horizontal, Theme.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .disabled(o.disabled && !isSelected(o.id))
        .opacity(o.disabled && !isSelected(o.id) ? 0.45 : 1)
        .onHover { if $0 { highlighted = o.id } }
    }

    func createRow(_ title: String) -> some View {
        Button { make(title) } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "plus").font(Theme.Glyph.regular)
                Text(createTitle(title)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.tight)
            .background(rowsEmpty ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .padding(Theme.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }

    /// With nothing else to pick, Return makes it, so the row shows as the one Return reaches.
    private var rowsEmpty: Bool { filtered.isEmpty }

    func make(_ title: String) {
        create?(title)
        query = ""
        if !multiple { open = false }
    }

    func step(_ delta: Int, in rows: [PickOption<ID>]) {
        guard !rows.isEmpty else { return }
        let i = highlighted.flatMap { id in rows.firstIndex { $0.id == id } } ?? (delta > 0 ? -1 : rows.count)
        highlighted = rows[min(max(i + delta, 0), rows.count - 1)].id
    }

    func choose(_ id: ID) {
        // Return on the highlighted row reaches here without the button, so the disabled check repeats.
        if options.first(where: { $0.id == id })?.disabled == true, !isSelected(id) { return }
        pick(id)
        if !multiple { open = false }
    }
}

/// One value from a data-driven list.
struct SearchSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [PickOption<Value>]
    var placeholder = String(localized: .designPick)

    var body: some View {
        SearchPicker(options: options, isSelected: { $0 == selection }, pick: { selection = $0 }) {
            ChipLabel(options.first { $0.id == selection }?.title ?? placeholder)
        }
    }
}

/// Several values from a data-driven list, kept in the order they were picked.
struct SearchMultiSelect<Value: Hashable>: View {
    @Binding var selection: [Value]
    let options: [PickOption<Value>]
    var placeholder = String(localized: .designPick)
    /// The chip text; defaults to the picked titles.
    var summary: String?
    /// For a tree: what picking or unpicking an option takes along with it, itself included.
    var subtree: ((Value) -> Set<Value>)?

    var body: some View {
        SearchPicker(options: options, isSelected: { selection.contains($0) }, pick: { id in
            let group = subtree?(id) ?? [id]
            if selection.contains(id) {
                selection.removeAll { group.contains($0) }
            } else {
                // Outline order, so the chip names the chapter rather than whichever section came first in the set.
                selection += options.map(\.id).filter { group.contains($0) && !selection.contains($0) }
            }
        }, multiple: true) {
            let titles = selection.compactMap { id in options.first { $0.id == id }?.title }
            // The count, then one title (cut off first when long): every title joined pushed a form row, and the sheet with it, past its width.
            ChipLabel(summary ?? titles.first.map { titles.count > 1 ? String(localized: .designPickedMany(titles.count, $0)) : $0 } ?? placeholder)
        }
    }
}

/// The app's segmented control: a gray track with the chosen option on a card-colored capsule.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    /// Line icons drawn in place of the labels, one per option; the label stays as the spoken name and the tooltip.
    var symbols: [String] = []
    /// For a bar of tools: washes of the text color instead of solid fills, and a track as tall as the bar's buttons.
    var compact = false
    /// A label's own color, where each option stands for a kind drawn in that color elsewhere (patch notes' chips).
    var inks: [Color?] = []
    @Environment(\.onGlass) private var onGlass

    var body: some View {
        let compact = compact || onGlass
        HStack(spacing: Theme.Space.xxs) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let chosen = selection == value
                Button { selection = value } label: {
                    Group {
                        if symbols.indices.contains(i) { LineIcon(symbol: symbols[i], filled: chosen) } else { Text(label).lineLimit(1) }
                    }
                        .fontWeight(chosen ? .semibold : .regular)
                        .foregroundStyle(inks.indices.contains(i) ? inks[i] ?? labelColor(chosen) : labelColor(chosen))
                        .padding(Theme.Inset.toggle)
                        .background(chosen ? (compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.tint)) : AnyShapeStyle(Theme.Palette.card)) : AnyShapeStyle(.clear), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pointing(.plain))
                .help(symbols.isEmpty ? "" : label)
                .accessibilityLabel(label)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(compact ? Theme.Space.xxs : Theme.Space.xs)
        .fixedSize()
        .background(compact ? AnyShapeStyle(Theme.Palette.text.opacity(Theme.Opacity.wash)) : AnyShapeStyle(Theme.Palette.fill), in: .capsule)
    }

    func labelColor(_ chosen: Bool) -> Color { chosen ? Theme.Palette.text : Theme.Palette.textSecondary }
}

/// Minute of the day as a chip. Drag sideways on the hours or the minutes to scrub them, or click one to set it on a clock
/// face; nothing is typed, so every value it can hold is a real time.
struct TimeMenu: View {
    @Binding var minute: Int
    var hours: ClosedRange<Int> = 0...23
    @State private var dial: TimeDial.Mode?

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            TimePart(value: Binding(get: { minute / 60 }, set: { minute = $0 * 60 + minute % 60 }), values: Array(hours), label: Self.hourLabel) { dial = .hour }
            Text(":").foregroundStyle(Theme.Palette.textTertiary)
            TimePart(value: Binding(get: { minute % 60 }, set: { minute = minute / 60 * 60 + $0 }), values: Array(stride(from: 0, to: 60, by: 5))) { dial = .minute }
        }
        .monospacedDigit()
        .chip()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(minute))
        .accessibilityAdjustableAction { direction in
            minute = (minute + (direction == .increment ? 5 : -5) + 1440) % 1440
        }
        .popover(item: $dial, arrowEdge: .bottom) { mode in
            TimeDial(minute: $minute, hours: hours, mode: mode) { dial = nil }
        }
    }

    /// Every clock time follows the system's 12- or 24-hour setting, as `.formatted(time: .shortened)` elsewhere does.
    static func label(_ m: Int) -> String {
        Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened)
    }

    /// `오후 1:00~2:15`: the system's own interval form, which names 오후 once and keeps a row's time on one line.
    static func range(_ start: Int, _ end: Int) -> String {
        let at = { (m: Int) in Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now)! }
        return end > start ? (at(start)..<at(end)).formatted(date: .omitted, time: .shortened) : label(start)
    }

    static var uses12Hour: Bool { DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false }

    /// The hour half of the chip in the same clock as `label`: `오후 1` or `13`.
    static func hourLabel(_ h: Int) -> String {
        guard uses12Hour else { return String(format: "%02d", h) }
        return "\(h < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol) \(h % 12 == 0 ? 12 : h % 12)"
    }
}

private struct TimePart: View {
    @Binding var value: Int
    let values: [Int]
    var label: (Int) -> String = { String(format: "%02d", $0) }
    let pick: () -> Void
    @State private var start: Int?

    var body: some View {
        Text(label(value))
            .padding(.horizontal, Theme.Space.xxs)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        let base = start ?? value
                        start = base
                        let steps = Int((g.translation.width / ScrubField.pointsPerStep).rounded())
                        // From the nearest allowed value, wrapping like a clock face: after the last comes the first.
                        let i = values.indices.min { abs(values[$0] - base) < abs(values[$1] - base) } ?? 0
                        value = values[((i + steps) % values.count + values.count) % values.count]
                    }
                    .onEnded { _ in start = nil }
            )
            .onTapGesture(perform: pick)
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .help(Text(.designDragOrPickHelp))
            // Only while scrubbing: the chip stays live behind an open dial, and the dial gives its own.
            .sensoryFeedback(.selection, trigger: value) { _, _ in start != nil }
    }
}

/// A clock face: click or drag around it to set the hour, which then turns to the minutes; setting those closes it.
/// The 24-hour clock puts 12–23 on an inner ring, so either clock is one turn of the hand.
private struct TimeDial: View {
    enum Mode: Hashable, Identifiable {
        case hour, minute
        var id: Self { self }
    }

    @Binding var minute: Int
    let hours: ClosedRange<Int>
    @State var mode: Mode
    let close: () -> Void
    @Environment(\.accent) private var accent
    /// Whether this press landed on a mark the menu allows; only then does releasing it move on.
    @State private var picked = false

    static let diameter: CGFloat = 224
    static let cell: CGFloat = 32
    static let outer = diameter / 2 - cell / 2 - Theme.Space.xs
    static let inner = outer - cell - Theme.Space.xs
    /// Presses inside this reach set nothing: the hub has no mark, and its angle is noise.
    static let hub = inner - cell / 2

    private var hour: Int { minute / 60 }
    private var twelve: Bool { TimeMenu.uses12Hour }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header
            face
        }
        .padding(Theme.Space.l)
        .sensoryFeedback(.selection, trigger: minute)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.xxs) {
                part(twelve ? "\(hour % 12 == 0 ? 12 : hour % 12)" : String(format: "%02d", hour), .hour)
                Text(":").foregroundStyle(Theme.Palette.textTertiary)
                part(String(format: "%02d", minute % 60), .minute)
            }
            .font(Theme.Typeface.figure)
            Spacer(minLength: 0)
            if twelve {
                // A toggle only when both halves hold an hour the menu allows; the day boundary (0–8) just names its
                // half, or its 12 would read as noon.
                if hours.contains(where: { $0 < 12 }), hours.contains(where: { $0 >= 12 }) {
                    Segmented(selection: Binding(get: { hour >= 12 }, set: { pm in setHour(hour % 12 + (pm ? 12 : 0)) }),
                              options: [(false, Calendar.current.amSymbol), (true, Calendar.current.pmSymbol)])
                } else {
                    Text(hour < 12 ? Calendar.current.amSymbol : Calendar.current.pmSymbol)
                        .font(Theme.Typeface.bodyStrong)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    private func part(_ text: String, _ m: Mode) -> some View {
        Button { withAnimation(.snappy) { mode = m } } label: {
            Text(text).foregroundStyle(mode == m ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .buttonStyle(.pointing(.plain))
    }

    /// The marks around the face: where each sits, the value it sets, and what it reads.
    private var marks: [(angle: Double, radius: CGFloat, value: Int, label: String)] {
        switch mode {
        case .minute:
            return (0..<12).map { (Double($0) * 30, Self.outer, $0 * 5, String(format: "%02d", $0 * 5)) }
        case .hour where twelve:
            let half = hour >= 12 ? 12 : 0
            return (0..<12).map { (Double($0) * 30, Self.outer, $0 + half, "\($0 == 0 ? 12 : $0)") }
        case .hour:
            return (0..<24).map { (Double($0 % 12) * 30, $0 < 12 ? Self.outer : Self.inner, $0, String(format: "%02d", $0)) }
        }
    }

    private var selected: Int { mode == .hour ? hour : minute % 60 }

    private var face: some View {
        let center = CGPoint(x: Self.diameter / 2, y: Self.diameter / 2)
        let marks = marks
        let chosen = marks.first { $0.value == selected }
        // Off the 5-minute marks (a time from a file) the hand still points at the exact minute, with no mark lit.
        let handAngle = chosen?.angle ?? Double(minute % 60) * 6
        let handRadius = chosen?.radius ?? Self.outer
        let tip = Self.point(handAngle, handRadius, center)
        return ZStack {
            Circle().fill(Theme.Palette.fill)
            Path { p in
                p.move(to: center)
                p.addLine(to: tip)
            }
            .stroke(accent.color, lineWidth: 2)
            Circle().fill(accent.color).frame(width: 6, height: 6).position(center)
            Circle().fill(accent.color).frame(width: Self.cell, height: Self.cell).position(tip)
            ForEach(marks, id: \.value) { mark in
                let allowed = mode == .minute || hours.contains(mark.value)
                Text(mark.label)
                    .font(mark.radius == Self.inner ? Theme.Typeface.caption : Theme.Typeface.body)
                    .monospacedDigit()
                    .foregroundStyle(mark.value == selected ? Theme.Palette.onFill
                                     : allowed ? (mark.radius == Self.inner ? Theme.Palette.textSecondary : Theme.Palette.text)
                                     : Theme.Palette.textTertiary.opacity(0.5))
                    .frame(width: Self.cell, height: Self.cell)
                    .position(Self.point(mark.angle, mark.radius, center))
                    .accessibilityLabel(mode == .hour ? TimeMenu.hourLabel(mark.value) : mark.label)
                    .accessibilityAddTraits(Self.traits(allowed: allowed, selected: mark.value == selected))
                    .accessibilityAction { if set(mark.value) { advance() } }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(.circle)
        .animation(.snappy, value: mode)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in if pick(at: g.location, center) { picked = true } }
                .onEnded { _ in
                    if picked { advance() }
                    picked = false
                }
        )
        #if os(macOS)
        .pointerStyle(.link)
        #endif
    }

    /// No button for a dimmed hour: pressing it does nothing.
    private static func traits(allowed: Bool, selected: Bool) -> AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if allowed { traits.formUnion(.isButton) }
        if selected { traits.formUnion(.isSelected) }
        return traits
    }

    private static func point(_ degrees: Double, _ radius: CGFloat, _ center: CGPoint) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(a), y: center.y - radius * cos(a))
    }

    private func pick(at p: CGPoint, _ center: CGPoint) -> Bool {
        let dx = p.x - center.x, dy = p.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= Self.hub else { return false }
        let degrees = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let slot = Int((degrees / 30).rounded()) % 12
        switch mode {
        case .minute:
            return set(slot * 5)
        case .hour where twelve:
            return set(slot + (hour >= 12 ? 12 : 0))
        case .hour:
            return set(slot + (distance < (Self.outer + Self.inner) / 2 ? 12 : 0))
        }
    }

    /// False for an hour outside `hours`, which leaves the time as it was.
    @discardableResult
    private func set(_ value: Int) -> Bool {
        if mode == .minute {
            minute = hour * 60 + value
            return true
        }
        guard hours.contains(value) else { return false }
        minute = value * 60 + minute % 60
        return true
    }

    private func setHour(_ h: Int) {
        // The other half may lack this hour; the nearest one the menu allows stands in.
        let h = hours.contains(h) ? h : hours.min { abs($0 - h) < abs($1 - h) }!
        minute = h * 60 + minute % 60
    }

    private func advance() {
        if mode == .hour { withAnimation(.snappy) { mode = .minute } } else { close() }
    }
}

/// A date (and time) chip that opens a calendar.
struct DateChip: View {
    @Binding var date: Date
    var showsTime = true
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Text(date.formatted(showsTime ? .dateTime.month().day().weekday().hour().minute() : .dateTime.year().month().day().weekday()))
                .monospacedDigit()
                .chip()
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            DatePanel(date: $date, showsTime: showsTime) { if !showsTime { open = false } }
                .padding(Theme.Space.l)
                .frame(width: 280)
        }
    }
}

/// The calendar and, with `showsTime`, the time menu and its presets: what a date chip opens.
struct DatePanel: View {
    @Environment(Workspace.self) private var workspace
    @Binding var date: Date
    var showsTime = true
    /// After a day is picked, for a date-only chip that closes then.
    var picked: () -> Void = {}

    static let presets = [9 * 60, 12 * 60, 18 * 60, 23 * 60 + 59]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            MonthCalendar(date: Binding(get: { date }, set: { day in
                date = workspace.calendar.date(byAdding: .minute, value: minuteOfDay, to: workspace.calendar.startOfDay(for: day)) ?? day
                picked()
            }))
            if showsTime {
                Divider()
                HStack(spacing: Theme.Space.s) {
                    Text(.designTime).foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    TimeMenu(minute: Binding(get: { minuteOfDay }, set: { setMinute($0) }))
                }
                // The four times run wider than the 280pt popover: in one row they squeezed into "오전 9…" or broke
                // "오전" from "9:00". Each keeps its own width and the last ones take a second row.
                FlowLayout(spacing: Theme.Space.tight) {
                    ForEach(Self.presets, id: \.self) { m in
                        Button(TimeMenu.label(m)) { setMinute(m) }
                            .lineLimit(1)
                            .buttonStyle(.pointing(.plain))
                            .font(Theme.Typeface.caption.monospacedDigit())
                            .foregroundStyle(m == minuteOfDay ? Theme.Palette.text : Theme.Palette.textSecondary)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, Theme.Space.xs)
                            .background(m == minuteOfDay ? Theme.Palette.fill : .clear, in: .capsule)
                    }
                }
            }
        }
    }

    var minuteOfDay: Int {
        let c = workspace.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func setMinute(_ m: Int) {
        let day = workspace.calendar.startOfDay(for: date)
        date = workspace.calendar.date(byAdding: .minute, value: m, to: day) ?? date
    }
}

/// A month grid that picks a day. Always six rows so the popover keeps its size between months.
struct MonthCalendar: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Binding var date: Date
    @State private var month: Date?

    var body: some View {
        let calendar = workspace.calendar
        let shown = month ?? calendar.dateInterval(of: .month, for: date)!.start
        let lead = (calendar.component(.weekday, from: shown) - calendar.firstWeekday + 7) % 7
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - lead, to: shown) }
        let columns = Array(repeating: GridItem(.fixed(34), spacing: Theme.Space.xxs), count: 7)
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text(shown.formatted(.dateTime.year().month(.wide))).font(Theme.Typeface.bodyStrong)
                Spacer()
                Button(.designToday) { month = nil; date = .now }
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Button { month = calendar.date(byAdding: .month, value: -1, to: shown) } label: { Image(systemName: "chevron.left") }
                Button { month = calendar.date(byAdding: .month, value: 1, to: shown) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.ghost)
            LazyVGrid(columns: columns, spacing: Theme.Space.xxs) {
                ForEach(0..<7, id: \.self) { i in
                    Text(ClassTime.weekdayNames[((calendar.firstWeekday - 1 + i) % 7 + 6) % 7])
                        .font(Theme.Typeface.label)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(height: 22)
                }
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: date)
                    let inMonth = calendar.isDate(day, equalTo: shown, toGranularity: .month)
                    Button { date = day } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(calendar.isDateInToday(day) ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
                            .monospacedDigit()
                            .foregroundStyle(selected ? Theme.Palette.onFill : inMonth ? Theme.Palette.text : Theme.Palette.textTertiary.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(selected ? accent.color : .clear, in: .circle)
                            .overlay { if calendar.isDateInToday(day) && !selected { Circle().strokeBorder(accent.color, lineWidth: 1.5) } }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.pointing(.plain))
                }
            }
        }
        .onChange(of: date) { _, new in
            if let m = month, !calendar.isDate(new, equalTo: m, toGranularity: .month) { month = nil }
        }
    }
}

extension View {
    /// The rounded gray capsule every inline control sits in.
    func chip() -> some View {
        padding(Theme.Inset.control)
            .surface(Theme.Palette.fill, in: .capsule)
            .contentShape(.capsule)
    }
}

/// More views to switch between than `Segmented` holds (2–4): a row of caption chips that wraps, each fully named,
/// the one picked in the accent's tint. Scrolled sideways, the last ones would hide.
struct ChipTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Environment(\.accent) private var accent

    var body: some View {
        FlowLayout(spacing: Theme.Space.tight) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                let on = value == selection
                Button { selection = value } label: {
                    Text(title)
                        .lineLimit(1)
                        .font(Theme.Typeface.caption.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? accent.ink : Theme.Palette.textSecondary)
                        .padding(Theme.Inset.toggle)
                        .background(on ? accent.tint : Theme.Palette.fill, in: .capsule)
                        .contentShape(TouchTarget())
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A filter field on the gray capsule.
struct SearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.textTertiary) }
                    .buttonStyle(.pointing(.plain))
            }
        }
        .chip()
    }
}

/// A `TextEditor` as tall as its text, from `lines.lowerBound` lines up to `lines.upperBound`, past which it scrolls.
/// Not `TextField(axis: .vertical)`: on the Mac its Return ends the field instead of breaking the line, and options
/// and rules are written one per line. Not a drag handle either: a touch has nothing to drag it with.
struct GrowingTextEditor: View {
    @Binding var text: String
    /// A point size, not a `Font`: the height is measured with the platform font.
    var size: CGFloat = Theme.Typeface.bodySize
    var lines: ClosedRange<Int> = 3...12
    /// The most it may grow to in a sheet, whose rows fit the window: fewer lines than `lines` allows there.
    var room: CGFloat?
    @State private var width: CGFloat = 0

    var body: some View {
        let height = Self.height(of: text, size: size, width: width, lines: lines, room: room)
        TextEditor(text: $text)
            .font(.system(size: size))
            .scrollContentBackground(.hidden)
            // Only once it scrolls. A text input keeps its bar then (a fading scroll area around it hides it for
            // everything inside), but the Mac's editor keeps a bar's width free for it, wrapping its text narrower than
            // the width measured here: the box came out a line short.
            .scrollIndicators(height.scrolls ? .automatic : .never)
            .frame(height: height.points)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Laid out by TextKit as the editor's text view lays it out. A hidden SwiftUI `Text` broke a long URL at other
    /// places than the editor did, a line short, and the last line scrolled out of a box that should have held it.
    static func height(of text: String, size: CGFloat, width: CGFloat, lines: ClosedRange<Int>, room: CGFloat? = nil) -> (points: CGFloat, scrolls: Bool) {
        let font = PlatformFont.systemFont(ofSize: size)
        let layout = NSLayoutManager()
        #if os(macOS)
        let line = layout.defaultLineHeight(for: font)
        #else
        let line = font.lineHeight
        #endif
        var used = line * CGFloat(lines.lowerBound)
        if width > 0 {
            let storage = NSTextStorage(string: text, attributes: [.font: font])
            // The container's default line padding is the editor's too.
            let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            // The used rect counts a trailing newline's empty line, where the editor's caret sits.
            used = layout.usedRect(for: container).height
        }
        // Whole lines that fit the room, never under the minimum.
        let fit = room.map { Int(($0 - 2 * inset) / line) } ?? lines.upperBound
        let cap = line * CGFloat(max(lines.lowerBound, min(lines.upperBound, fit)))
        return (min(max(used, line * CGFloat(lines.lowerBound)), cap).rounded(.up) + 2 * inset, used > cap)
    }

    // UITextView keeps its text 8pt from its top and bottom edges; the Mac's text view sets it at the edges.
    #if os(iOS)
    private static let inset: CGFloat = 8
    #else
    private static let inset: CGFloat = 0
    #endif
}

extension Binding {
    /// An array element that survives its removal: a removed row's controls still read their binding while they go away,
    /// and a plain `$array[i]` then reads past the end and crashes.
    func element<E: Identifiable>(id: E.ID, fallback: E) -> Binding<E> where Value == [E] {
        Binding<E>(get: { wrappedValue.first { $0.id == id } ?? fallback },
                   set: { new in if let j = wrappedValue.firstIndex(where: { $0.id == id }) { wrappedValue[j] = new } })
    }

    func element<E>(at i: Int, fallback: E) -> Binding<E> where Value == [E] {
        Binding<E>(get: { wrappedValue.indices.contains(i) ? wrappedValue[i] : fallback },
                   set: { new in if wrappedValue.indices.contains(i) { wrappedValue[i] = new } })
    }
}

extension View {
    /// A field on the window frame or a glass sidebar (the search field, a PDF's find): a wash of the text color with
    /// an edge, as tall as the toolbar's buttons. A solid field stood alone on the material.
    func toolbarField() -> some View {
        padding(.horizontal, Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .toolbarSurface()
    }

    /// Toolbar buttons that belong together, held in one capsule like the search field: loose on the frame, plain
    /// glyphs read as stray marks beside it. As tall as the field, the buttons' own height: padded above and below,
    /// the groups stood taller than the field and the toolbar row clipped their edges. No side padding either, so the
    /// buttons' inset hover sits as far from every edge.
    func toolbarGroup() -> some View {
        frame(height: Theme.Size.toolbarButton).toolbarSurface()
    }

    private func toolbarSurface() -> some View {
        background(Theme.Palette.text.opacity(Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
    }
}
