import FolioActions
import FolioDomain
import SwiftUI

/// The lecture the schedule says is under way or next, not made yet: a dashed row. Starting its rough note or a
/// recording makes the session first; 휴강 saves it cancelled, so the suggestion moves to the next lecture.
struct SuggestedSessionRow: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    var showsCourse = false
    let openNote: (UUID) -> Void
    /// On the sessions page, where a wrong suggestion is the cue that the class times changed.
    var editTimes: (() -> Void)?

    var body: some View {
        let date = item.suggestion.date
        let today = workspace.isStudyToday(date)
        HStack(spacing: Theme.Space.m) {
            if showsCourse {
                Text(date.formatted(date: .omitted, time: .shortened)).timeColumn().font(Theme.Typeface.caption).monospacedDigit().fixedSize()
                CourseMark(workspace, item.courseId)
                // Today's own list: the day goes without saying.
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
                    // The day is beside it already.
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
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .opacity(today ? 1 : 0.85)
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
    }
}

struct SuggestedSessionActions: View {
    @Environment(Workspace.self) private var workspace
    let item: Workspace.SuggestedSession
    /// In Today's narrow column the note button is an icon.
    var compact = false
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    private var menu: SessionMenuModel { SessionMenuModel(workspace: workspace, courseId: item.courseId) }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if menu.isToday(item) {
                Button { if let id = menu.roughNote(item) { openNote(id) } } label: {
                    if compact { Image(systemName: "square.and.pencil").accessibilityLabel(Text(.sessionsRoughNote)) } else { Text(.sessionsRoughNote) }
                }
                .buttonStyle(.prominent)
                .help(Text(.sessionsRoughNoteHelp))
            } else {
                Button(.sessionsMake) { menu.make(item) }.buttonStyle(.pointing(.bordered))
            }
            Menu { SuggestedSessionItems(item: item, primary: false, openNote: openNote, editTimes: editTimes) } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary).frame(width: 24, height: 24).contentShape(.rect)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(.sessionsSuggestionMenuHelp))
        }
    }
}

extension View {
    // As wide as the widest time in the column's font: a fixed width truncated or wrapped `오후 1:00`.
    // Verbatim: it is a measuring sample of the formatted time, never shown.
    func timeColumn() -> some View {
        ZStack(alignment: .leading) { Text(verbatim: "오후 12:00").hidden(); self }.lineLimit(1)
    }
}
