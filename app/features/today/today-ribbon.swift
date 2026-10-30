import FolioDomain
import SwiftUI

/// Chips, the date, a line of counts, and the week beside them.
struct TodayHeader: View {
    let model: TodayModel
    let summary: TodaySummary
    let classes: [TodayModel.RibbonClass]
    let reviews: TodayModel.Reviews

    var body: some View {
        // The counts include ended classes, so the line moves on as the day does.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let now = model.workspace.now
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: Theme.Space.xl) {
                    heading(now: now)
                    Spacer(minLength: 0)
                    week
                }
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    heading(now: now)
                    week
                }
            }
        }
        // The page's own gaps fit block to block; the date sits apart from the day below it, as in the mockup.
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
    }

    func heading(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(model.heading(summary, now: now)).font(Theme.Typeface.pageTitle)
            HStack(spacing: Theme.Space.m) {
                let pieces = model.summaryLine(classes: classes, summary: summary, reviews: reviews, now: now)
                ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                    if i > 0 { CourseDot(color: Theme.Palette.lineStrong, size: Theme.Space.xs) }
                    Text(Self.counts(piece.text, urgent: piece.urgent))
                }
            }
            .font(Theme.Typeface.bodyLarge)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1)
        }
        .fixedSize()
    }

    /// The bold runs of a count line in full text color, or danger when the count needs doing today.
    static func counts(_ text: AttributedString, urgent: Bool) -> AttributedString {
        var text = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = urgent ? Theme.Palette.danger : Theme.Palette.text
        }
        return text
    }

    var week: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(model.week(around: summary.studyDay)) { day in
                VStack(spacing: Theme.Space.xs) {
                    Text(day.weekday).font(Theme.Typeface.label)
                    Text("\(day.day.day)").font(Theme.Typeface.bodyStrong).monospacedDigit()
                    HStack(spacing: Theme.Space.xxs) {
                        ForEach(day.courses.prefix(4), id: \.self) { CourseDot(color: model.workspace.accent($0).color, size: Theme.Space.tight) }
                    }
                    .frame(height: Theme.Space.tight)
                }
                .foregroundStyle(day.isToday ? Theme.Palette.text : Theme.Palette.textTertiary)
                .frame(width: 40)
                .padding(.vertical, Theme.Space.s)
                .background {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.Palette.card)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The study day's classes laid out on an hour axis, with the time now and today's deadlines on it.
struct DayRibbonCard: View {
    let model: TodayModel
    let summary: TodaySummary
    let classes: [TodayModel.RibbonClass]
    let go: (UUID, CourseSection) -> Void
    let openNote: (UUID) -> (UUID) -> Void
    @State private var opened: String?

    static let label: CGFloat = 16
    static let track: CGFloat = 48

    var body: some View {
        let ribbon = model.ribbon(classes, on: summary.studyDay)
        let due = summary.deadlines.filter(\.isToday).count
        let note = due > 0 ? String(localized: .todayRibbonNoteDue(classes.count, due)) : String(localized: .todayRibbonNote(classes.count))
        Block(String(localized: .todayClasses), note: classes.isEmpty ? nil : note) {
            Card(padding: Theme.Space.l) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    GeometryReader { proxy in
                        canvas(ribbon, width: proxy.size.width, now: model.workspace.now)
                    }
                    .frame(height: Self.label * 2 + Self.track + Theme.Space.xs * 2)
                }
            }
        }
    }

    func canvas(_ ribbon: DayRibbon, width: CGFloat, now: Date) -> some View {
        let trackTop = Self.label + Theme.Space.xs
        let x = { (date: Date) in ribbon.position(of: date) * width }
        return ZStack(alignment: .topLeading) {
            Theme.Palette.lineSoft.frame(width: width, height: 1).offset(y: trackTop + Self.track / 2)
            if classes.isEmpty {
                freeDay(now: now).frame(width: width, height: Self.track).offset(y: trackTop)
            }
            ForEach(classes) { item in
                let left = x(item.start), right = x(item.end)
                block(item, now: now)
                    // A hair of paper between back-to-back classes.
                    .frame(width: max(Theme.Space.s, right - left - Theme.Space.xxs), height: Self.track)
                    .offset(x: left, y: trackTop)
            }
            ForEach(dues(), id: \.date) { due in
                // The time reads leftward from the flag, so a midnight deadline stays inside the card.
                flag(due.date, items: due.items)
                    .frame(width: 80, alignment: .trailing)
                    .offset(x: x(due.date) - 80 + Theme.Space.s, y: 0)
            }
            if ribbon.contains(now) {
                let at = x(now)
                Theme.Palette.text.frame(width: Theme.Space.xxs, height: Self.track + Theme.Space.s)
                    .clipShape(.capsule)
                    .offset(x: at - Theme.Space.xxs / 2, y: trackTop - Theme.Space.xs)
                // A flag's time takes the label row near it; the line alone still says where now is.
                if !dues().contains(where: { abs(x($0.date) - at) < 80 }) {
                    Text(model.time(now)).font(Theme.Typeface.label).monospacedDigit().fixedSize()
                        .frame(width: 80, alignment: .center)
                        .offset(x: at - 40, y: 0)
                }
            }
            ForEach(ribbon.ticks, id: \.self) { hour in
                let at = Double(hour - ribbon.startHour) / Double(ribbon.endHour - ribbon.startHour) * width
                let first = hour == ribbon.ticks.first, last = hour == ribbon.ticks.last
                Text(tick(hour, on: ribbon)).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary).fixedSize()
                    .frame(width: 80, alignment: first ? .leading : last ? .trailing : .center)
                    .offset(x: first ? at : last ? at - 80 : at - 40, y: trackTop + Self.track + Theme.Space.xs)
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// `오전 9 · 12 · 오후 3 · 6 · 9 · 자정`: am/pm on the first tick and where it turns, as on a timetable. Noon reads
    /// plainly as 12, so the turn is marked at the next tick.
    func tick(_ hour: Int, on ribbon: DayRibbon) -> String {
        if hour == 24 { return String(localized: .todayRibbonMidnight) }
        let calendar = model.workspace.calendar
        let before = ribbon.ticks.last { $0 < hour && $0 != 12 }
        let marked = hour != 12 && before.map { ($0 >= 12) != (hour >= 12) } ?? true
        let number = "\(hour % 12 == 0 ? 12 : hour % 12)"
        return marked ? "\(hour < 12 ? calendar.amSymbol : calendar.pmSymbol) \(number)" : number
    }

    @ViewBuilder func block(_ item: TodayModel.RibbonClass, now: Date) -> some View {
        let accent = model.workspace.accent(item.courseId)
        let ongoing = now >= item.start && now < item.end, ended = now >= item.end
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
        // One line each, cut short: a block is an hour and a bit wide, and the full name is in the tooltip.
        let label = VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(model.title(item.courseId)).font(Theme.Typeface.caption.weight(.semibold)).foregroundStyle(accent.ink)
            // The axis below already says 오전 or 오후; with it the time no longer fits an hour-wide block.
            Text(item.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())).font(Theme.Typeface.label.weight(.regular)).monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
        }
        .lineLimit(1)
        .padding(Theme.Space.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(item.suggested == nil ? accent.tint : .clear, in: shape)
        .overlay {
            if item.suggested != nil {
                shape.strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            } else if ongoing {
                shape.strokeBorder(accent.color)
            }
        }
        .clipShape(shape)
        .opacity(ended ? Theme.Opacity.ended : 1)
        // Unfaded paper under a faded block, so the track line behind it does not show through.
        .background(Theme.Palette.card, in: shape)
        .contentShape(shape)
        .help("\(model.title(item.courseId)) · \(item.name) · \(model.time(item.start)) – \(model.time(item.end))")
        if let suggested = item.suggested {
            // Not made yet: what starting it needs sits in a popover, as on the class's own row elsewhere.
            Button { opened = item.id } label: { label }
                .buttonStyle(.pointing(.plain))
                .popover(isPresented: Binding { opened == item.id } set: { if !$0 { opened = nil } }) {
                    SuggestedSessionRow(item: suggested, showsCourse: true, openNote: openNote(item.courseId))
                        .padding(Theme.Space.m)
                        .frame(width: 420)
                }
                .contextMenu { SuggestedSessionItems(item: suggested, primary: true, openNote: openNote(item.courseId)) }
        } else if let sessionId = item.sessionId {
            Button { go(item.courseId, .sessions) } label: { label }
                .buttonStyle(.pointing(.plain))
                .contextMenu { SessionMenu(courseId: item.courseId, sessionId: sessionId, openNote: openNote(item.courseId)) { go(item.courseId, .sessions) } }
        }
    }

    /// Today's deadlines by their time, those due together on one flag.
    func dues() -> [(date: Date, items: [TodaySummary.DeadlineItem])] {
        let today = summary.deadlines.filter(\.isToday)
        return Dictionary(grouping: today) { $0.assignment.due ?? .distantFuture }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func flag(_ date: Date, items: [TodaySummary.DeadlineItem]) -> some View {
        let help = items.map { String(localized: .todayRibbonDueHelp($0.assignment.title, model.time(date))) }.joined(separator: "\n")
        return Button { if let first = items.first { model.edit(first) } } label: {
            HStack(spacing: Theme.Space.xxs) {
                Text(model.time(date)).monospacedDigit()
                Image(systemName: "flag.fill")
            }
            .font(Theme.Typeface.label)
            .foregroundStyle(Theme.Palette.danger)
            .fixedSize()
        }
        .buttonStyle(.pointing(.plain))
        .help(help)
        .accessibilityLabel(help)
    }

    func freeDay(now: Date) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(.todayRibbonFree).foregroundStyle(Theme.Palette.textSecondary)
            if let next = model.nextClassLine(after: now) {
                CourseDot(color: Theme.Palette.lineStrong, size: Theme.Space.xs)
                Text(.todayRibbonNext(next.when)).foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Space.xs) {
                    CourseMark(model.workspace, next.courseId, inline: true)
                    Text(model.title(next.courseId)).fontWeight(.semibold).foregroundStyle(model.workspace.accent(next.courseId).ink)
                }
            }
        }
        .font(Theme.Typeface.caption)
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}
