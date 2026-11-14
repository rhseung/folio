import FolioActions
import FolioDomain
import SwiftUI

struct SuggestedSessionRow: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    var showsCourse = false
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let date = item.suggestion.date
        let today = workspace.isStudyToday(date)
        HStack(spacing: Theme.Space.m) {
            if showsCourse {
                Text(date.formatted(date: .omitted, time: .shortened)).timeColumn().font(Theme.Typeface.caption).monospacedDigit()
                    .fixedSize()
                CourseMark(workspace, item.courseId)
                Text(workspace.course(item.courseId)?.title ?? "").lineLimit(1)
                    .help(Text(.sessionsSuggested))
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(date.formatted(.dateTime.month().day())).font(Theme.Typeface.bodyStrong).monospacedDigit()
                    Text(SessionsModel.weekdayTime(date, in: workspace.calendar))
                        .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                }
                .frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(.sessionsLecture).font(Theme.Typeface.bodyStrong)
                    if !item.suggestion.room.isEmpty {
                        Text(item.suggestion.room).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: Theme.Space.m)
            if today, let link = item.suggestion.link.flatMap(OnlineLink.url) { JoinOnlineButton(url: link).fixedSize() }
            SuggestedSessionActions(item: item, compact: showsCourse, openNote: openNote, editTimes: editTimes).fixedSize()
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(
                Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
        .opacity(today ? 1 : 0.85)
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
    }
}
