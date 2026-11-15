import FolioDomain
import SwiftUI

struct ClassSettings: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Block(String(localized: .settingsClassStart)) { ClassStartCard(model: model) }
        let courses = model.classStartCourses
        if !courses.isEmpty {
            Block(String(localized: .settingsClassStartCourses)) {
                Card {
                    ForEach(Array(courses.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == courses.count - 1) {
                            CourseMark(model.workspace, course.id)
                            Text(course.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            Menu {
                                ForEach(ClassStartSettings.Item.allCases, id: \.self) { item in
                                    Toggle(
                                        item.label,
                                        isOn: Binding(
                                            get: { model.follows(item, course: course.id) },
                                            set: { model.setFollows($0, item, course: course.id) }))
                                }
                            } label: {
                                ChipLabel(model.exceptionLabel(course.id))
                            }
                            .menuButton()
                            .fixedSize()
                        }
                    }
                }
            }
        }
        SettingBlock(.classTime, model: model)
        TranscriptionSettings()
    }
}

private struct ClassStartCard: View {
    @Bindable var model: SettingsModel
    @State private var details = false

    var body: some View {
        let s = model.settings.classStart
        let any = model.startsSomething
        Card(clipped: true) {
            ClassStartPicture(items: model.classStartItems, settings: s, title: model.referenceTitle)
                .padding([.horizontal, .top], Theme.Space.m)
                .padding(.bottom, Theme.Space.s)
            Theme.Palette.lineSoft.frame(height: 1).padding(.leading, Theme.Space.l)
            FormRow(label: String(localized: .settingsClassStartItems), last: !any) {
                ToggleChips(
                    selection: $model.classStartItems,
                    options: ClassStartSettings.Item.allCases.map { .init(value: $0, label: $0.label, symbol: $0.symbol) })
            }
            if model.isOn(.recording) {
                FormRow(label: String(localized: .settingsClassStartRecordingMode)) {
                    Segmented(
                        selection: $model.settings.classStart.recording,
                        options: [
                            (.start, String(localized: .settingsClassStartNow)), (.ask, String(localized: .settingsClassStartAsk)),
                        ])
                }
            }
            if model.opensPages {
                FormRow(label: String(localized: .settingsClassStartOpenIn)) {
                    PictureChoice(
                        selection: $model.settings.classStart.openIn,
                        options: [
                            (.splitTab, String(localized: .settingsClassStartOpenInSplit)),
                            (.currentTab, String(localized: .settingsClassStartOpenInCurrent)),
                        ]
                    ) { LayoutSketch(openIn: $0) }
                }
            }
            if any {
                FormRow(label: String(localized: .settingsClassStartScreen)) {
                    ChoiceMenu(
                        selection: $model.settings.classStart.screen,
                        options: [
                            (.notify, String(localized: .settingsClassStartNotify)), (.front, String(localized: .settingsClassStartFront)),
                        ])
                }
                DisclosureRow(label: String(localized: .settingsDetails), isOpen: $details, last: true) {
                    let rows = detailRows
                    if model.isOn(.recording) { RecordingSpanRow(model: model, last: rows.last == .span) }
                    if model.isOn(.roughNote) {
                        FormRow(label: String(localized: .settingsClassStartNoNote), last: rows.last == .note) {
                            ChoiceMenu(
                                selection: $model.settings.classStart.roughNote,
                                options: [
                                    (.create, String(localized: .settingsClassStartCreate)),
                                    (.openExisting, String(localized: .settingsClassStartSkip)),
                                ])
                        }
                    }
                    if model.isOn(.lecture) {
                        FormRow(label: String(localized: .settingsClassStartLectureCount)) {
                            ChoiceMenu(
                                selection: $model.settings.classStart.allLectures,
                                options: [
                                    (false, String(localized: .settingsClassStartFirstLecture)),
                                    (true, String(localized: .settingsClassStartAllLectures)),
                                ])
                        }
                        FormRow(label: String(localized: .settingsClassStartResume), last: true) {
                            Switch(isOn: $model.settings.classStart.resumesLecture)
                        }
                    }
                }
            }
        }
    }

    enum DetailRow { case span, note, lecture }

    var detailRows: [DetailRow] {
        [model.isOn(.recording) ? .span : nil, model.isOn(.roughNote) ? .note : nil, model.isOn(.lecture) ? .lecture : nil].compactMap {
            $0
        }
    }
}

private struct RecordingSpanRow: View {
    @Bindable var model: SettingsModel
    var last = false

    var body: some View {
        let s = model.settings.classStart
        FormRow(label: String(localized: .settingsClassStartSpan), detail: model.recordingSpanTimes, last: last) {
            FlowLayout(spacing: Theme.Space.s, centered: true) {
                HStack(spacing: Theme.Space.xs) {
                    minutes($model.settings.classStart.recordingOffsetMinutes, .classRecordingOffset)
                    Text(s.recordingOffsetMinutes < 0 ? .settingsClassStartMinutesBefore : .settingsUnitMinutesAfter)
                }
                Text(verbatim: "~").foregroundStyle(Theme.Palette.textTertiary)
                if s.stopsRecording {
                    HStack(spacing: Theme.Space.xs) {
                        Text(s.stopAfterMinutes < 0 ? .settingsClassStartBeforeEnd : .settingsClassStartAfterEnd)
                        minutes($model.settings.classStart.stopAfterMinutes, .classStopAfter)
                        Text(s.stopAfterMinutes < 0 ? .settingsClassStartMinutesBefore : .settingsUnitMinutesAfter)
                    }
                } else {
                    Text(.settingsClassStartManualStop)
                }
                HStack(spacing: Theme.Space.s) {
                    Text(.settingsClassStartAutoStop)
                    Switch(isOn: $model.settings.classStart.stopsRecording)
                }
                .padding(.leading, Theme.Space.s)
            }
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }

    func minutes(_ value: Binding<Int>, _ item: SettingItem) -> some View {
        ScrubField(value: value, range: item.range, magnitude: true).foregroundStyle(Theme.Palette.text)
    }
}

// 창 하나를 아이콘 크기로 줄여 그린 그림이다. 탭과 칸의 비율은 그림 자신의 것이라 화면의 토큰과 맞추지 않는다.
private struct LayoutSketch: View {
    let openIn: ClassStartSettings.OpenIn

    static let tab = CGSize(width: 10, height: 4)
    static let newTab = CGSize(width: 12, height: 4)
    static let sidePane: CGFloat = 14
    static let strong = 0.45
    static let quiet = 0.25
    static let idle = 0.3

    var body: some View {
        let split = openIn == .splitTab
        RoundedRectangle(cornerRadius: Theme.Radius.small)
            .strokeBorder(.foreground.opacity(Theme.Opacity.soft))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.xxs) {
                        Capsule().fill(.foreground.opacity(split ? Self.idle : 1)).frame(Self.tab)
                        if split { Capsule().fill(.foreground).frame(Self.newTab) }
                    }
                    HStack(spacing: Theme.Space.xxs) {
                        RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(.foreground.opacity(split ? Self.strong : Self.quiet))
                        RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(.foreground.opacity(split ? Self.quiet : Self.strong))
                            .frame(width: Self.sidePane)
                    }
                }
                .padding(Theme.Space.xs)
            }
    }
}

private struct ClassStartPicture: View {
    let items: Set<ClassStartSettings.Item>
    let settings: ClassStartSettings
    let title: String

    enum Pane: Hashable { case today, note, lecture(Int) }

    var opensPages: Bool { items.contains(.roughNote) || items.contains(.lecture) }
    var notifies: Bool { settings.screen == .notify && !items.isEmpty }

    var panes: [Pane] {
        let lectures = items.contains(.lecture) ? (0..<(settings.allLectures ? 2 : 1)).map(Pane.lecture) : []
        guard opensPages else { return [.today] }
        if settings.openIn == .currentTab { return Array(([items.contains(.roughNote) ? .note : .today] + lectures).prefix(3)) }
        return Array((lectures + (items.contains(.roughNote) ? [.note] : [])).prefix(3))
    }

    var newTab: Bool { opensPages && settings.openIn == .splitTab }

    var body: some View {
        window
            .opacity(notifies ? Theme.Opacity.planned : 1)
            .padding(.top, notifies ? Theme.Space.xxl + Theme.Space.l : 0)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity)
            .background(Theme.Palette.column, in: .rect(cornerRadius: Theme.Radius.control))
            .overlay(alignment: .topTrailing) { if notifies { banner.padding(Theme.Space.s) } }
            .font(.system(size: 10))  // design: one-off, the type of a window drawn small
            .accessibilityHidden(true)
    }

    var window: some View {
        VStack(spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Theme.Palette.line).frame(width: Theme.Size.smallDot, height: Theme.Size.smallDot)
                    }
                }
                .padding(.trailing, Theme.Space.xs)
                tab(String(localized: .settingsPreviewToday), chosen: !newTab)
                if newTab { tab(title, chosen: true, focused: true).layoutPriority(-1) }
                Spacer(minLength: 0)
                if items.contains(.recording) { recordingMark }
            }
            .frame(height: Theme.Space.xl)
            Group {
                if items.isEmpty {
                    Text(.settingsPreviewNothing).foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.tile))
                } else {
                    HStack(spacing: Theme.Space.xs) { ForEach(panes, id: \.self, content: pane) }
                }
            }
            .frame(height: Theme.Size.classPreview)
            .overlay(alignment: .bottom) {
                if items.contains(.recording), settings.recording == .ask { askCard.padding(.bottom, Theme.Space.s) }
            }
        }
        .padding(.horizontal, Theme.Space.tight)
        .padding(.bottom, Theme.Space.tight)
        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
        .shadow(Theme.Shadow.raised)
    }

    func tab(_ name: String, chosen: Bool, focused: Bool = false) -> some View {
        Text(name).lineLimit(1)
            .foregroundStyle(focused ? Theme.Palette.info : chosen ? Theme.Palette.text : Theme.Palette.textTertiary)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xxs)
            .background(chosen ? Theme.Palette.card : .clear, in: .capsule)
            .overlay { if focused { Capsule().strokeBorder(Theme.Palette.info) } }
    }

    var recordingMark: some View {
        let live = settings.recording == .start
        return HStack(spacing: Theme.Space.xs) {
            Circle().fill(Theme.Palette.danger).frame(width: Theme.Size.smallDot, height: Theme.Size.smallDot)
            Text(live ? .settingsPreviewRecording : .settingsPreviewWaiting)
        }
        .foregroundStyle(live ? Theme.Palette.danger : Theme.Palette.textSecondary)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xxs)
        .background(live ? Theme.Palette.dangerFill : .clear, in: .capsule)
        .overlay { if !live { Capsule().strokeBorder(Theme.Palette.line) } }
    }

    @ViewBuilder func pane(_ p: Pane) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            switch p {
            case .today:
                Text(.settingsPreviewToday).foregroundStyle(Theme.Palette.textTertiary)
                ForEach([1.0, 0.8, 0.65], id: \.self) { w in lines(w, height: 8) }
            case .note:
                HStack {
                    Text(.settingsClassStartRoughNote).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: 0)
                    if settings.roughNote == .create { Text(.settingsPreviewNewNote).foregroundStyle(Theme.Palette.info) }
                }
                ForEach([0.7, 1.0, 0.85, 0.4], id: \.self) { w in lines(w, height: 4) }
            case .lecture(let i):
                Text(.settingsClassStartLecture).foregroundStyle(Theme.Palette.textTertiary)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Capsule().fill(Theme.Palette.textTertiary.opacity(Theme.Opacity.faded)).frame(
                        width: Theme.Size.layoutGlyph.width, height: Theme.Size.stripe)
                    RoundedRectangle(cornerRadius: Theme.Radius.mark).fill(Theme.Palette.info.opacity(Theme.Opacity.zoneAlt))
                }
                .padding(Theme.Space.xs)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small).strokeBorder(Theme.Palette.lineSoft))
                .overlay(alignment: .bottomTrailing) {
                    Text(settings.resumesLecture && i == 0 ? .settingsPreviewResume : .settingsPreviewFirstPage)
                        .foregroundStyle(Theme.Palette.info)
                        .padding(.horizontal, Theme.Space.tight)
                        .background(Theme.Palette.info.opacity(Theme.Opacity.tint), in: .capsule)
                        .padding(Theme.Space.xs)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(Theme.Space.tight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.tile))
    }

    func lines(_ width: Double, height: CGFloat) -> some View {
        GeometryReader { g in
            Capsule().fill(Theme.Palette.fill).frame(width: g.size.width * width, height: height)
        }
        .frame(height: height)
    }

    var askCard: some View {
        HStack(spacing: Theme.Space.s) {
            Text(.settingsClassStartRecording)
            Text(.settingsPreviewStart).fontWeight(.semibold).foregroundStyle(Theme.Palette.info)
            Text(.settingsPreviewLater).foregroundStyle(Theme.Palette.textTertiary)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .shadow(Theme.Shadow.lifted)
    }

    var banner: some View {
        HStack(alignment: .top, spacing: Theme.Space.tight) {
            Image(systemName: "bell").foregroundStyle(Theme.Palette.info)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).fontWeight(.semibold)
                Text(
                    items.contains(.recording) && settings.recording == .start ? .settingsPreviewStartedRecording : .settingsPreviewStarted
                )
                .foregroundStyle(Theme.Palette.textSecondary)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.tight)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .shadow(Theme.Shadow.lifted)
    }
}

// Whisper 모델은 기기마다 내려받으므로 settings.json이 아니라 이 기기의 선택이다.
private struct TranscriptionSettings: View {
    @AppStorage(TranscriptionEngine.storageKey) private var engine: TranscriptionEngine = .standard
    private var whisper: WhisperModel { .shared }

    var body: some View {
        Block(String(localized: .settingsTranscription)) {
            Card {
                FormRow(label: String(localized: .settingsTranscriptionEngine), device: true) {
                    ChoiceMenu(
                        selection: $engine,
                        options: [
                            (.whisper, String(localized: .settingsTranscriptionWhisper)),
                            (.apple, String(localized: .settingsTranscriptionApple)),
                        ])
                }
                FormRow(
                    label: String(localized: .settingsWhisperModel), detail: String(localized: .settingsWhisperModelDetail), device: true,
                    last: true
                ) {
                    if let fraction = whisper.downloading {
                        ProgressView(value: fraction).progressViewStyle(.linear).frame(width: Theme.Size.meter)
                        Text(.settingsWhisperDownloading(Int(fraction * 100))).monospacedDigit().foregroundStyle(
                            Theme.Palette.textSecondary)
                    } else if whisper.ready {
                        Text(.settingsWhisperReady).foregroundStyle(Theme.Palette.textSecondary)
                        Button(.settingsWhisperDelete, role: .destructive) { whisper.delete() }.buttonStyle(.ghost)
                            .disabled(whisper.busy)
                            .help(whisper.busy ? String(localized: .settingsWhisperDeleteBusy) : "")
                    } else {
                        if let failure = whisper.failure {
                            Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger).lineLimit(2)
                        }
                        Button(.settingsWhisperDownload) { whisper.download() }.buttonStyle(.pointing(.bordered))
                    }
                }
            }
        }
    }
}
