import FolioActions
import FolioDomain
import SwiftUI

struct SessionCard: View {
    @Environment(\.accent) private var accent
    let model: SessionsModel
    let course: LoadedCourse
    let session: Session
    var now = Date.now
    let openNote: (UUID) -> Void
    @Environment(\.openLink) private var openLink
    @Environment(\.openURL) private var openURL
    @Environment(\.itemSheets) private var sheets
    @State private var showsGaps = false
    @State private var editAfterGaps = false

    static let linesRoom: CGFloat = 240

    var body: some View {
        let file = course.file
        let timing = model.timing(of: session, in: file, now: now)
        let live = timing.live
        let fade = session.isCancelled ? Theme.Opacity.ended : 1

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.l) {
                ClassCard.Tile(
                    month: model.month(session.date), day: model.day(session.date),
                    ink: live ? accent.ink : Theme.Palette.text, monthInk: live ? accent.ink : Theme.Palette.textTertiary,
                    fill: live ? accent.tint : Theme.Palette.page
                )
                .opacity(fade)
                // 둘이 다 들어가지 않으면 알약을 줄 아래로 내린다. iPhone에서 나란히 두면 단원 선택기가 한 줄에 한
                // 글자씩 끊기고 행이 카드 밖으로 나갔다. 줄의 ideal 크기를 고정해 두어, 넓은 창에서 긴 제목은 행을 접지
                // 않고 예전처럼 잘린다.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Space.l) {
                        lines(file, live: live).frame(idealWidth: Self.linesRoom).opacity(fade)
                        trailing(file, live: live, expected: timing.expectedEnd).opacity(fade)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        lines(file, live: live).opacity(fade)
                        trailing(file, live: live, expected: timing.expectedEnd).opacity(fade)
                    }
                }
                ClassCard.MenuButton(help: String(localized: .sessionsMenuHelp)) { menuItems }
            }
            if timing.offersStart { actions(file) }
        }
        .padding(.vertical, Theme.Space.m)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 60)
        .background {
            GeometryReader { proxy in
                Theme.Palette.card.overlay(alignment: .leading) {
                    if let progress = timing.progress { accent.tint.frame(width: proxy.size.width * progress) }
                }
            }
            .clipShape(.rect(cornerRadius: ClassCard.radius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ClassCard.radius).strokeBorder(
                live ? accent.color.opacity(Theme.Opacity.liveEdge) : Theme.Palette.line, lineWidth: 1)
        }
        .contentShape(.rect)
        .contextMenu { menuItems }
    }

    func lines(_ file: CourseFile, live: Bool) -> some View {
        let late = model.lateMark(session, in: file)
        let cancelled = session.isCancelled
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Text(model.title(of: session, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(model.hasSubject(session, in: file) ? Theme.Palette.text : Theme.Palette.textTertiary)
                    .help(file.title(of: session, calendar: model.calendar))
                    // 강조색 테두리와 타일만 눈에 보이는 표시라서 VoiceOver에는 낱말이 필요하다.
                    .accessibilityValue(live ? String(localized: .sessionsNow) : "")
                SessionKindChip(kind: session.kind)
                if let late { Chip(late.label, tone: late.value == .late ? .warning : late.value == .absent ? .danger : .plain) }
                let gaps = model.leftGaps(session, in: file, now: now)
                if !gaps.isEmpty {
                    Button {
                        showsGaps = true
                    } label: {
                        Circle().fill(Theme.Palette.warning).frame(width: Theme.Size.dot, height: Theme.Size.dot).contentShape(
                            TouchTarget())
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.wrapUpLeftHelp(model.gapsLine(gaps))))
                    .accessibilityLabel(Text(.wrapUpLeftHelp(model.gapsLine(gaps))))
                    .popover(isPresented: $showsGaps, arrowEdge: .bottom) { gapsPanel(gaps) }
                }
            }
            HStack(spacing: Theme.Space.tight) {
                Text(model.dayLine(session.date, end: model.end(of: session, in: file))).monospacedDigit().lineLimit(1).fixedSize()
                if model.link(of: session, in: file) != nil && !cancelled {
                    Image(systemName: "video").help(Text(.sessionsOnline))
                }
                if !cancelled {
                    SessionUnitsButton(course: course, session: session, compact: model.hasSubject(session, in: file), separated: true)
                }
            }
            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func gapsPanel(_ gaps: [WrapUpItem]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(.wrapUpLeftHeading).font(Theme.Typeface.sectionTitle).foregroundStyle(Theme.Palette.textSecondary)
            ForEach(gaps, id: \.self) { gap in
                HStack(spacing: Theme.Space.s) {
                    Circle().fill(Theme.Palette.warning).frame(width: Theme.Size.dot, height: Theme.Size.dot)
                    Text(gap.label).font(Theme.Typeface.body).foregroundStyle(Theme.Palette.text)
                }
            }
            if model.offersWrapUp(session) {
                Button(.commonEditEllipsis) {
                    editAfterGaps = true
                    showsGaps = false
                }
                .buttonStyle(.ghost)
                .padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.l)
        .presentationCompactAdaptation(.popover)
        .onDisappear {
            if editAfterGaps {
                editAfterGaps = false
                sheets.present(.session(SessionSheetRequest(course: course.id, session: session.id)))
            }
        }
    }

    @ViewBuilder func trailing(_ file: CourseFile, live: Bool, expected: Date) -> some View {
        let recordings = model.menu.recordings(of: session)
        let recorder = model.workspace.recorder
        HStack(spacing: Theme.Space.s) {
            if recordings.contains(where: { $0.id == recorder.current }) {
                ClassCard.Tag(title: String(localized: .sessionsRecording), symbol: "waveform", tone: .danger)
                    .symbolEffect(.variableColor.iterative, isActive: recorder.state == .recording)
            } else if let last = recordings.last {
                ClassCard.Pill(
                    title: model.recordingsLabel(recordings.count), symbol: "waveform", help: String(localized: .sessionsRecordingPlayHelp)
                ) { play(last) }
            }
            switch model.review(of: session, in: file, now: now) {
            case .done(let id):
                ClassCard.Pill(
                    title: String(localized: .sessionsReviewDone), tone: .success, help: String(localized: .sessionsOpenReviewNote)
                ) { openNote(id) }
            case .writing(let id):
                ClassCard.Pill(
                    title: String(localized: .sessionsReviewWriting), tone: .warning, help: String(localized: .sessionsSlotReviewDraftHelp)
                ) { openNote(id) }
            case .missing where !live:
                ClassCard.Pill(
                    title: String(localized: .sessionsReviewMissing), tone: .danger, help: String(localized: .sessionsSlotReviewMakeHelp)
                ) { open(.review) }
            case .missing, nil:
                EmptyView()
            }
            if live {
                ClassCard.Tag(title: model.minutesLeft(until: expected, now: now), tone: .accent)
            }
        }
    }

    func actions(_ file: CourseFile) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) { actionButtons(file) }.padding(.leading, ClassCard.tile + Theme.Space.l)
            HStack(spacing: Theme.Space.s) { actionButtons(file) }
            VStack(alignment: .leading, spacing: Theme.Space.s) { actionButtons(file) }
        }
    }

    @ViewBuilder func actionButtons(_ file: CourseFile) -> some View {
        if let link = model.link(of: session, in: file) { JoinOnlineButton(url: link, prominent: true) }
        if !model.workspace.recorder.isActive {
            ItemButton(source: menuSource, command: .record).buttonStyle(.pointing(.bordered))
                .help(Text(.sessionsRecordHelp))
        }
        Button(String(localized: session.roughNoteId == nil ? .sessionsRoughNote : .sessionsOpenRoughNote), systemImage: "doc.text") {
            open(.rough)
        }
        .buttonStyle(.pointing(.bordered))
    }

    var menuItems: some View {
        SessionMenu(courseId: course.id, sessionId: session.id, host: .own, openNote: openNote)
    }

    var menuSource: SessionMenuSource {
        SessionMenuSource(
            workspace: model.workspace, courseId: course.id, session: session, host: .own, now: now, openNote: openNote,
            openLink: openLink, openURL: openURL, sheets: sheets)
    }

    func open(_ kind: NoteKind) {
        if let id = model.menu.note(kind, of: session) { openNote(id) }
    }

    func play(_ recording: Recording) { openLink(AppLink(.recording, recording.id), course: course.id) }
}
