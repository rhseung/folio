import FolioCore
import FolioDomain
import SwiftUI

// 넓은 폭의 회차 표다. 줄은 주차, 열은 수업 요일과 끝의 "그 밖"이다.
struct SessionTableView: View {
    @Environment(\.accent) private var accent
    @Environment(\.itemSheets) private var sheets
    @Bindable var model: SessionsModel
    let course: LoadedCourse
    let table: SessionTable

    var wide: Bool { model.form == .wide }
    var gutter: CGFloat { wide ? Theme.Size.weekGutter : Theme.Size.weekGutterCompact }

    var body: some View {
        Card(clipped: true) {
            WeekColumns(gutter: gutter) {
                Color.clear
                ForEach(table.columns) { column in
                    head(model.columnTitle(column), detail: model.columnDetail(column), strong: true)
                }
                head(String(localized: .sessionsTableOther), detail: String(localized: .sessionsTableOtherDetail), strong: false)
            }
            .frame(minHeight: Theme.Size.rowHeight)
            // LazyVStack을 쓰지 않는다. 아직 그리지 않은 줄의 높이를 어림해서, 이번 주로 미끄러져 가는 스크롤이
            // 엉뚱한 곳에 멈추거나 도착한 뒤 튀었다. 한 학기는 20주 안팎이라 모두 그려도 무겁지 않다.
            VStack(spacing: 0) {
                ForEach(table.weeks) { week in row(week).id(week.id) }
            }
        }
    }

    func head(_ title: String, detail: String, strong: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(title).font(Theme.Typeface.bodyStrong).foregroundStyle(strong ? Theme.Palette.text : Theme.Palette.textSecondary)
                .lineLimit(1).fixedSize()
            if wide {
                Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, wide ? Theme.Space.m : Theme.Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    func row(_ week: SessionTable.Week) -> some View {
        WeekColumns(gutter: gutter) {
            weekHead(week)
            ForEach(week.cells) { cell in self.cell(cell, last: cell.weekday == nil) }
        }
        .background(week.isThisWeek ? accent.color.opacity(Theme.Opacity.wash) : .clear)
        .overlay(alignment: .top) { Theme.Palette.lineSoft.frame(height: 1) }
    }

    func weekHead(_ week: SessionTable.Week) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(model.weekLabel(week)).font(Theme.Typeface.bodyStrong)
                .foregroundStyle(week.isThisWeek ? accent.ink : Theme.Palette.textSecondary).lineLimit(1)
            // 날짜는 칸마다 있으므로 주차 여백에 구간을 다시 쓰지 않는다.
            if wide && week.isExamWeek {
                Text(.sessionsExamWeek).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger).lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.leading, wide ? Theme.Space.m : Theme.Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        // 강조색과 바탕만 눈에 보이는 표시라서 VoiceOver에는 낱말이 필요하다.
        .accessibilityValue(
            [week.isThisWeek ? String(localized: .sessionsThisWeek) : nil, week.isExamWeek ? String(localized: .sessionsExamWeek) : nil]
                .compactMap { $0 }.joined(separator: ", "))
    }

    func cell(_ cell: SessionTable.Cell, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let day = cell.day { dayChip(day, today: cell.isToday, has: !cell.entries.isEmpty) }
            ForEach(cell.entries) { entry in
                SessionTableItem(model: model, course: course, entry: entry, table: table, other: last)
            }
        }
        .padding(wide ? Theme.Space.s : Theme.Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: Theme.Size.touchTarget + Theme.Space.xl)
        .background {
            // 빈 날을 누르면 그날로 회차를 추가한다.
            if cell.entries.isEmpty, let day = cell.day {
                Button {
                    if let request = model.addRequest(on: day, in: table) { sheets.present(.session(request)) }
                } label: {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .accessibilityLabel(model.spokenEmpty(day))
            }
        }
        .overlay(alignment: .leading) { Theme.Palette.lineSoft.frame(width: 1) }
    }

    func dayChip(_ day: LocalDate, today: Bool, has: Bool) -> some View {
        Text(model.chipDay(day))
            .font(Theme.Typeface.caption.weight(today || has ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(today ? Theme.Palette.onFill : has ? Theme.Palette.textSecondary : Theme.Palette.textTertiary)
            // 숫자는 칸의 왼쪽 끝에 붙인다. 날짜 자리는 오늘이든 아니든 원 높이 하나라서 같은 줄 블록의 위치가 같고,
            // 오늘의 원은 칸의 위와 왼쪽에서 같은 여백만큼 떨어진다.
            .padding(.horizontal, today ? Theme.Space.xs : 0)
            .frame(minWidth: today ? Theme.Size.dayMark : nil, minHeight: Theme.Size.dayMark)
            .background { if today { Capsule().fill(accent.fill) } }
            .padding(.bottom, Theme.Space.xxs)
            .accessibilityHidden(true)
    }
}
