import FolioDomain
import SwiftUI

struct TimeMenu: View {
    @Binding var minute: Int
    var hours: ClosedRange<Int> = 0...23
    @State private var dial: TimeDial.Mode?

    var body: some View {
        HStack(spacing: Theme.Space.xxs) {
            TimePart(
                value: Binding(get: { minute / 60 }, set: { minute = $0 * 60 + minute % 60 }), values: Array(hours), label: Self.hourLabel
            ) { dial = .hour }
            Text(":").foregroundStyle(Theme.Palette.textTertiary)
            TimePart(
                value: Binding(get: { minute % 60 }, set: { minute = minute / 60 * 60 + $0 }), values: Array(stride(from: 0, to: 60, by: 5))
            ) { dial = .minute }
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

    static func label(_ m: Int) -> String {
        Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened)
    }

    static func range(_ start: Int, _ end: Int) -> String {
        let at = { (m: Int) in Calendar.current.date(bySettingHour: m / 60 % 24, minute: m % 60, second: 0, of: .now)! }
        return end > start ? (at(start)..<at(end)).formatted(date: .omitted, time: .shortened) : label(start)
    }

    static var uses12Hour: Bool { DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false }

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
            .sensoryFeedback(.selection, trigger: value) { _, _ in start != nil }
    }
}

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
    @State private var picked = false

    static let diameter: CGFloat = 224
    static let cell: CGFloat = 32
    static let outer = diameter / 2 - cell / 2 - Theme.Space.xs
    static let inner = outer - cell - Theme.Space.xs
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
                if hours.contains(where: { $0 < 12 }), hours.contains(where: { $0 >= 12 }) {
                    Segmented(
                        selection: Binding(get: { hour >= 12 }, set: { pm in setHour(hour % 12 + (pm ? 12 : 0)) }),
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
        Button {
            withAnimation(.snappy) { mode = m }
        } label: {
            Text(text).foregroundStyle(mode == m ? Theme.Palette.text : Theme.Palette.textTertiary)
        }
        .buttonStyle(.pointing(.plain))
    }

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
                    .foregroundStyle(
                        mark.value == selected
                            ? Theme.Palette.onFill
                            : allowed
                                ? (mark.radius == Self.inner ? Theme.Palette.textSecondary : Theme.Palette.text)
                                : Theme.Palette.textTertiary.opacity(0.5)
                    )
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
        let h = hours.contains(h) ? h : hours.min { abs($0 - h) < abs($1 - h) }!
        minute = h * 60 + minute % 60
    }

    private func advance() {
        if mode == .hour { withAnimation(.snappy) { mode = .minute } } else { close() }
    }
}
