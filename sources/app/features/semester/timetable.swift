import FolioActions
import FolioDomain
import SwiftUI

struct Timetable<Menu: View>: View {
    let model: SemesterModel
    let layout: TimetableLayout
    var today: Int?
    let open: (Course) -> Void
    @ViewBuilder let menu: (Course) -> Menu

    static var hourHeight: CGFloat { 48 }
    static var gutter: CGFloat { 28 }

    var body: some View {
        let (days, first, last) = (layout.days, layout.first, layout.last)
        let height = CGFloat(max(last - first, 1)) * Self.hourHeight
        Card(padding: Theme.Space.m) {
            if layout.slots.isEmpty {
                EmptyLine(String(localized: .semesterTimetableEmpty)).padding(Theme.Space.xs)
            } else {
                VStack(spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.xs) {
                        Color.clear.frame(width: Self.gutter, height: 1)
                        ForEach(days, id: \.self) { day in
                            Text(ClassTime.weekdayNames[day - 1])
                                .font(Theme.Typeface.label)
                                .foregroundStyle(day == today ? Theme.Palette.text : Theme.Palette.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(first..<last, id: \.self) { hour in
                                Text("\(hour)").font(Theme.Typeface.label.weight(.regular)).monospacedDigit()
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .frame(height: Self.hourHeight, alignment: .top)
                            }
                        }
                        .frame(width: Self.gutter, alignment: .trailing)
                        ForEach(days, id: \.self) { day in
                            column(layout.slots(on: day), first: first, height: height)
                                .background(
                                    day == today ? Theme.Palette.fill.opacity(0.5) : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                        }
                    }
                    .background(alignment: .top) {
                        VStack(spacing: 0) {
                            ForEach(first..<last, id: \.self) { _ in
                                Theme.Palette.lineSoft.frame(height: 1).frame(height: Self.hourHeight, alignment: .top)
                            }
                        }
                        .padding(.leading, Self.gutter + Theme.Space.xs)
                    }
                }
            }
        }
    }

    // shortcut: 같은 날 같은 시각의 수업 둘은 서로 겹쳐 그려진다. 그런 일이 생기면 열을 나눈다.
    func column(_ slots: [(course: Course, time: ClassTime)], first: Int, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(Array(slots.enumerated()), id: \.offset) { _, item in
                let (course, slot) = item
                let accent = model.workspace.accent(course.id)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(course.title).font(Theme.Typeface.caption.weight(.semibold)).lineLimit(2)
                    Text(TimeMenu.label(slot.startMinute) + (slot.room.isEmpty ? "" : " · \(slot.room)"))
                        .font(Theme.Typeface.label.weight(.regular)).monospacedDigit().lineLimit(1)
                }
                .foregroundStyle(accent.ink)
                .padding(.horizontal, Theme.Space.tight)
                .padding(.vertical, Theme.Space.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(height: max(CGFloat(slot.endMinute - slot.startMinute) / 60 * Self.hourHeight - 2, 20))
                .background(accent.tint, in: .rect(cornerRadius: Theme.Radius.control - 2))
                .overlay(alignment: .leading) { accent.color.frame(width: 4).clipShape(.rect(cornerRadius: Theme.Radius.mark)) }
                .clipShape(.rect(cornerRadius: Theme.Radius.control - 2))
                .opens { open(course) }
                .contextMenu { menu(course) }
                .offset(y: CGFloat(slot.startMinute - first * 60) / 60 * Self.hourHeight + 1)
                .help(
                    "\(course.title) · \(TimeMenu.range(slot.startMinute, slot.endMinute))" + (slot.room.isEmpty ? "" : " · \(slot.room)"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}
