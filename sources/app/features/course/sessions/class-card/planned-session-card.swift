import FolioActions
import FolioDomain
import SwiftUI

struct PlannedSessionCard: View {
    @Environment(\.accent) private var accent
    @Environment(Workspace.self) private var workspace
    let model: SessionsModel
    let item: Workspace.SuggestedSession
    let openNote: (UUID) -> Void
    var editTimes: (() -> Void)?

    var body: some View {
        let date = item.suggestion.date
        let today = workspace.isStudyToday(date)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ClassCard.Tile(month: model.month(date), day: model.day(date), fill: .clear, dashed: true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(.sessionsClass).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    HStack(spacing: Theme.Space.tight) {
                        Text(model.plannedLine(item)).monospacedDigit().lineLimit(1)
                        if item.suggestion.link != nil {
                            Image(systemName: "video").help(Text(.sessionsOnline))
                        }
                    }
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ClassCard.MenuButton(help: String(localized: .sessionsSuggestionMenuHelp)) {
                    SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes)
                }
            }
            if today {
                HStack(spacing: Theme.Space.s) {
                    if let link = item.suggestion.link.flatMap(OnlineLink.url) { JoinOnlineButton(url: link, prominent: true) }
                    Button(.sessionsRecord, systemImage: "record.circle") { model.menu.record(item) }
                        .buttonStyle(.pointing(.bordered)).disabled(model.menu.isRecording)
                    Button(.sessionsRoughNote, systemImage: "doc.text") { if let id = model.menu.roughNote(item) { openNote(id) } }
                        .buttonStyle(.pointing(.bordered)).help(Text(.sessionsRoughNoteHelp))
                }
                .padding(.leading, ClassCard.tile + Theme.Space.l)
            }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 60)
        .background(Theme.Palette.card.opacity(Theme.Opacity.planned), in: .rect(cornerRadius: ClassCard.radius))
        .background(Theme.Palette.page, in: .rect(cornerRadius: ClassCard.radius))
        .overlay {
            RoundedRectangle(cornerRadius: ClassCard.radius).strokeBorder(
                Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
        .help(Text(.sessionsPlannedHelp))
    }
}
