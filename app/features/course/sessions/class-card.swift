import FolioActions
import FolioDomain
import SwiftUI

enum ClassCard {
    static let tile: CGFloat = 44
    static let menu: CGFloat = 28
    static let radius = Theme.Radius.card

    struct Tile: View {
        let month: String
        let day: String
        var ink: Color = Theme.Palette.text
        var monthInk: Color = Theme.Palette.textTertiary
        var fill: Color = Theme.Palette.page
        var dashed = false

        var body: some View {
            VStack(spacing: 0) {
                Text(month).font(Theme.Typeface.label).foregroundStyle(monthInk)
                Text(day).font(Theme.Typeface.figureSmall.weight(.bold)).foregroundStyle(ink)
            }
            .frame(width: ClassCard.tile, height: ClassCard.tile)
            .background(fill, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
    }

    /// The capsule a card's trailing row is made of. A state nothing opens (recording now, minutes left) is a bare tag,
    /// and `Pill` wraps the same tag in a button, so the row keeps one height and font whichever it holds.
    struct Tag: View {
        @Environment(\.accent) private var accent
        let title: String
        var symbol: String?
        var tone: Tone = .plain

        var body: some View {
            HStack(spacing: Theme.Space.xs) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            // Fixed-width digits so a countdown ticking each minute doesn't jiggle the row.
            .font(Theme.Typeface.label.monospacedDigit())
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 24)
            .background(fill, in: .capsule)
            .fixedSize()
        }

        private var foreground: Color {
            switch tone {
            case .plain: Theme.Palette.textSecondary
            case .accent: accent.ink
            default: tone.foreground
            }
        }

        private var fill: Color {
            switch tone {
            case .accent: accent.color.opacity(Theme.Opacity.onTint)
            case .success: Theme.Palette.success.opacity(Theme.Opacity.tint)
            default: tone.fill
            }
        }
    }

    struct Pill: View {
        let title: String
        var symbol: String?
        var tone: Tone = .plain
        var help: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Tag(title: title, symbol: symbol, tone: tone).contentShape(.capsule)
            }
            .buttonStyle(.pointing(.plain))
            .fixedSize()
            .help(help)
        }
    }

    struct MenuButton<Items: View>: View {
        let help: String
        @ViewBuilder var items: Items

        var body: some View {
            Menu { items } label: {
                Image(systemName: "ellipsis").foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: ClassCard.menu, height: ClassCard.menu).contentShape(.circle)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless).pointingHand()
            .fixedSize()
            .help(Text(help))
        }
    }
}

/// A class the schedule still holds, not saved: an empty dashed slot. Its menu makes the session first, so a 휴강 or an
/// absence known weeks ahead has something to hang on; on its day it offers the same one-click start a session does.
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
        // Half the card's white over the page, but opaque, so an exam card tucked in behind doesn't show through.
        .background(Theme.Palette.card.opacity(Theme.Opacity.planned), in: .rect(cornerRadius: ClassCard.radius))
        .background(Theme.Palette.page, in: .rect(cornerRadius: ClassCard.radius))
        .overlay {
            RoundedRectangle(cornerRadius: ClassCard.radius).strokeBorder(Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .contentShape(.rect)
        .contextMenu { SuggestedSessionItems(item: item, primary: true, openNote: openNote, editTimes: editTimes) }
        .help(Text(.sessionsPlannedHelp))
    }
}

/// An exam outside class time, at its own date: in red whether taken or not, with how far off while it is ahead.
/// A score is a grade and stays on the grades page.
struct ExamMarkerRow: View {
    let model: SessionsModel
    let exam: Exam
    let date: Date

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            ClassCard.Tile(month: model.month(date), day: model.day(date), ink: Theme.Palette.danger, monthInk: Theme.Palette.danger,
                           fill: Theme.Palette.danger.opacity(Theme.Opacity.tint))
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold))
                Text(exam.title).font(Theme.Typeface.bodyLarge.weight(.bold)).lineLimit(1).fixedSize()
                Text(model.examLine(exam, date)).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                Capsule().fill(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge)).frame(minWidth: Theme.Space.xl, maxWidth: .infinity).frame(height: 2)
                if let days = model.examDays(exam, now: model.workspace.now) {
                    Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true)
                }
            }
            .foregroundStyle(Theme.Palette.danger)
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 52)
    }
}

/// Exams held in the class's time, as a card tucked in behind the class with only its top line showing. The class
/// stays the row: the exam is something that happens in it.
struct ClassExamCard: ViewModifier {
    let model: SessionsModel
    let exams: [Exam]
    let now: Date
    /// How far the card runs on under the class, so it reads as behind it rather than above it.
    static let tuck: CGFloat = 8

    func body(content: Content) -> some View {
        if exams.isEmpty {
            content
        } else {
            VStack(spacing: 0) {
                card
                content
                    // On the class's own shape, so its text casts none.
                    .background { RoundedRectangle(cornerRadius: ClassCard.radius).fill(.clear).shadow(color: .black.opacity(0.06), radius: 3, y: -2) }
                    .padding(.top, -Self.tuck)
            }
            // Room above, so a tucked-in exam reads as its own class's and not the one before.
            .padding(.top, Theme.Space.s)
        }
    }

    var card: some View {
        VStack(spacing: Theme.Space.xxs) {
            ForEach(exams) { exam in
                HStack(spacing: Theme.Space.l) {
                    Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold)).frame(width: ClassCard.tile)
                    HStack(spacing: Theme.Space.s) {
                        Text(exam.title).font(Theme.Typeface.bodyStrong.weight(.bold)).lineLimit(1).fixedSize()
                        if let time = model.examTime(exam) {
                            Text(time).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let days = model.examDays(exam, now: now) { Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true) }
                }
                .frame(minHeight: 24)
            }
        }
        .foregroundStyle(Theme.Palette.danger)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s + Self.tuck)
        .padding(.leading, Theme.Space.xs)
        .padding(.trailing, ClassCard.tile)
        .background(Theme.Palette.dangerFill, in: .rect(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius)
                .strokeBorder(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge), lineWidth: 1)
        }
        // Narrower than the class, as a card further back would be.
        .padding(.horizontal, Theme.Space.m)
    }
}
