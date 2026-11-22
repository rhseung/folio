import FolioCore
import FolioDomain
import SwiftUI

// 좁은 폭의 회차 목록이다. 주차 머리 아래에 일정이 있는 날만 날짜 타일과 함께 쌓는다.
struct SessionAgendaView: View {
    @Environment(\.accent) private var accent
    @Environment(\.itemSheets) private var sheets
    @Bindable var model: SessionsModel
    let course: LoadedCourse
    let table: SessionTable

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            ForEach(table.weeks) { week in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    head(week)
                    ForEach(week.agenda) { day in self.day(day) }
                }
                .id(week.id)
            }
        }
    }

    func head(_ week: SessionTable.Week) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(model.weekLabel(week)).font(Theme.Typeface.bodyStrong)
                .foregroundStyle(week.isThisWeek ? accent.ink : Theme.Palette.textSecondary)
            Text(model.weekRange(week)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            if week.isExamWeek { Text(.sessionsExamWeek).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
            if week.agenda.isEmpty { Text(.sessionsTableEmpty).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(week.isThisWeek ? String(localized: .sessionsThisWeek) : "")
    }

    func day(_ day: SessionAgendaDay) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let month = day.month {
                Text(model.month(month)).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.horizontal, Theme.Space.xs)
            }
            HStack(alignment: .top, spacing: Theme.Space.s) {
                tile(day)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(day.entries) { entry in
                        SessionTableItem(model: model, course: course, entry: entry, table: table, minHeight: Theme.Size.sessionListBlock)
                    }
                }
            }
        }
    }

    // 날짜 타일을 누르면 그날로 회차를 추가한다.
    func tile(_ day: SessionAgendaDay) -> some View {
        Button {
            if let request = model.addRequest(on: day.day, in: table) { sheets.present(.session(request)) }
        } label: {
            VStack(spacing: 0) {
                Text(model.weekday(day.day)).font(Theme.Typeface.label)
                    .foregroundStyle(day.isToday ? accent.ink : Theme.Palette.textTertiary)
                Text(model.dayNumber(day.day)).font(Theme.Typeface.dayFigure)
                    .foregroundStyle(day.isToday ? Theme.Palette.onFill : Theme.Palette.text)
                    .frame(width: Theme.Size.agendaToday, height: Theme.Size.agendaToday)
                    .background { if day.isToday { Circle().fill(accent.fill) } }
            }
            .frame(width: Theme.Size.dayColumn)
            .frame(minHeight: Theme.Size.touchTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .accessibilityLabel(model.spokenEmpty(day.day))
    }
}
