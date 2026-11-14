import FolioDomain
import SwiftUI

struct FirstRunView: View {
    @State private var model: FirstRunModel
    @State private var pickingFolder = false
    @State private var addingSemester = false
    @State private var addingCourse = false
    @State private var width: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    init(workspace: Workspace, step: FirstRunStep = .welcome) {
        _model = State(initialValue: FirstRunModel(workspace: workspace, step: step))
    }

    private var narrow: Bool { width > 0 && width < Theme.Size.firstRunNarrow }

    var body: some View {
        Group {
            if narrow { column } else { framed }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.choose(url) }
        }
        .sheet(isPresented: $addingSemester) {
            AddSemesterSheet(workspace: model.workspace) { id in
                if let id { model.chosenSemester = id }
            }
        }
        .sheet(isPresented: $addingCourse) {
            if let semester = model.semester { AddCourseSheet(workspace: model.workspace, semester: semester) { _ in } }
        }
        .task(id: model.step) {
            if model.step == .permissions { await model.refreshPermissions() }
        }
        #if DEBUG
        .task { await FirstRunDebug.run(model) }
        #endif
    }

    // MARK: Frames

    private var framed: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: Theme.Size.sidebar)
            panel
                .background(Theme.Palette.page, in: .rect(cornerRadius: Theme.Radius.floating))
                .clipShape(.rect(cornerRadius: Theme.Radius.floating))
                .overlay { RoundedRectangle(cornerRadius: Theme.Radius.floating).strokeBorder(Theme.Palette.lineSoft) }
                .padding([.trailing, .bottom], Theme.Size.panelInset)
                #if os(macOS)
            .padding(.top, Theme.Size.panelInset)
                #endif
        }
        #if os(macOS)
        .ignoresSafeArea(.container, edges: .top)
        .background { TrafficLights(center: TitleRowEdges.lights) { _ in } }
        .background(Theme.Palette.frameTint.ignoresSafeArea())
        .containerBackground(colorScheme == .light ? .thinMaterial : .regularMaterial, for: .window)
        #else
        .background(Theme.Palette.window.ignoresSafeArea())
        #endif
    }

    private var column: some View {
        VStack(spacing: 0) {
            HStack {
                if model.canGoBack {
                    Button {
                        model.back()
                    } label: {
                        Image(systemName: "chevron.left").frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
                    }
                    .buttonStyle(.pointing(.plain))
                    .accessibilityLabel(Text(.firstRunBack))
                }
                Spacer()
            }
            .frame(height: Theme.Size.touchTarget)
            .padding(.horizontal, Theme.Space.s)
            ScrollView {
                content
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: Theme.Space.m) {
                if model.trouble == nil { dots }
                primary.frame(maxWidth: .infinity)
                if model.offersLater {
                    Button(.firstRunLater) { model.later() }.buttonStyle(.ghost)
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Palette.page.ignoresSafeArea())
    }

    private var dots: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(FirstRunStep.allCases, id: \.self) { step in
                CourseDot(color: step == model.step ? Theme.Palette.text : Theme.Palette.line)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Step list

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            #if os(macOS)
            TitleDrag().frame(height: Theme.Size.toolbarRow)
            #else
            Color.clear.frame(height: Theme.Space.l)
            #endif
            HStack(spacing: Theme.Space.s) {
                AppMark()
                Text(.firstRunAppName).font(Theme.Typeface.figureMedium)
            }
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.m)
            ForEach(model.steps, id: \.self) { stepRow($0) }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s)
        .foregroundStyle(Theme.Palette.chromeText)
    }

    private func stepRow(_ step: FirstRunStep) -> some View {
        let done = model.isDone(step)
        let on = step == model.step
        return Button {
            model.go(to: step)
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: done ? "checkmark" : step.symbol).frame(width: Theme.Size.tile)
                Text(step.title).lineLimit(1)
                Spacer(minLength: Theme.Space.xs)
                if model.marksOptional(step) {
                    Text(.firstRunOptional).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(on ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
            .foregroundStyle(on ? Theme.Palette.text : done ? Theme.Palette.textTertiary : Theme.Palette.chromeText)
            .padding(.horizontal, Theme.Space.s)
            .frame(height: Self.stepHeight)
            .background(on ? Theme.Palette.sidebarSelection : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .disabled(!model.isReachable(step))
    }

    #if os(iOS)
    private static let stepHeight = Theme.Size.touchTarget
    #else
    private static let stepHeight = Theme.Size.toolbarButton
    #endif

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: Theme.Size.firstRunColumn, alignment: .leading)
                    .padding(.horizontal, Theme.Space.xxl)
                    .padding(.top, Theme.Space.xxl + Theme.Space.l)
                    .padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: .infinity)
            }
            Theme.Palette.lineSoft.frame(height: 1)
            HStack(spacing: Theme.Space.s) {
                if model.offersLater {
                    Button(.firstRunLater) { model.later() }.buttonStyle(.ghost)
                }
                Spacer()
                if model.canGoBack { Button(.firstRunBack) { model.back() } }
                primary
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l)
        }
        .controlSize(.large)
    }

    private var primary: some View {
        Button {
            model.proceed()
        } label: {
            Text(model.primaryTitle).frame(maxWidth: narrow ? .infinity : nil)
        }
        .buttonStyle(.prominent)
        .controlSize(.large)
        .disabled(!model.canContinue)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let trouble = model.trouble {
                reconnect(trouble)
            } else {
                switch model.step {
                case .welcome: welcome
                case .folder: folder
                case .term: term
                case .profile: profile
                case .permissions: permissions
                case .claude: claude
                }
            }
        }
    }

    private func header(_ title: LocalizedStringResource, _ subtitle: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.Typeface.pageTitle)
            Text(subtitle).font(Theme.Typeface.bodyLarge).foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).foregroundStyle(Theme.Palette.textSecondary).frame(width: Theme.Size.tile)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                AppMark(side: Theme.Size.appMarkLarge)
                header(.firstRunAppName, .firstRunWelcomeSubtitle)
            }
            Card {
                CardRow {
                    icon("doc.text"); Text(.firstRunWelcomeMaterials).font(Theme.Typeface.bodyStrong)
                }
                CardRow {
                    icon("waveform"); Text(.firstRunWelcomeRecording).font(Theme.Typeface.bodyStrong)
                }
                CardRow(last: true) {
                    icon("arrow.trianglehead.2.clockwise"); Text(.firstRunWelcomeReview).font(Theme.Typeface.bodyStrong)
                }
            }
        }
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header(.firstRunStepFolder, .firstRunFolderSubtitle)
            VStack(spacing: Theme.Space.m) {
                option(.fresh, detail: .firstRunFreshDetail)
                option(.existing, detail: .firstRunExistingDetail)
            }
        }
    }

    private func option(_ start: FolderStart, detail: LocalizedStringResource) -> some View {
        let on = model.start == start
        return VStack(spacing: 0) {
            Button {
                if model.choose(start) { pickingFolder = true }
            } label: {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: start == .fresh ? "folder.badge.plus" : "folder")
                        .font(Theme.Typeface.bodyLarge)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: Theme.Size.optionTile, height: Theme.Size.optionTile)
                        .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(start == .fresh ? .firstRunFresh : .firstRunExisting).font(Theme.Typeface.bodyLarge.weight(.semibold))
                        Text(detail).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Space.s)
                    Circle()
                        .strokeBorder(on ? Theme.Palette.chromeSelected : Theme.Palette.lineStrong, lineWidth: on ? 6 : 1.5)
                        .frame(width: Theme.Size.radio, height: Theme.Size.radio)
                }
                .padding(Theme.Space.l)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .accessibilityAddTraits(on ? .isSelected : [])
            if on, let path = model.pickedPath {
                Theme.Palette.lineSoft.frame(height: 1)
                CardRow {
                    Text(path).font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Theme.Space.s)
                    Button(.firstRunOtherFolder) { pickingFolder = true }
                }
                CardRow(last: true) {
                    if let problem = model.pickedProblem {
                        Text(problem).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(model.pickedSummary, id: \.self) { tag($0) }
                    }
                }
            }
        }
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(on ? Theme.Palette.chromeSelected : Theme.Palette.lineSoft, lineWidth: on ? 2 : 1)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textSecondary)
            .padding(Theme.Inset.tag)
            .background(Theme.Palette.fill, in: Capsule())
    }

    private var term: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header(.firstRunStepTerm, .firstRunTermSubtitle)
            Block(String(localized: .firstRunCurrentTerm)) {
                Card {
                    if let semester = model.semester {
                        FormRow(label: String(localized: .firstRunSemester)) {
                            Menu {
                                ForEach(model.semesters) { s in
                                    Button {
                                        model.chosenSemester = s.id
                                    } label: {
                                        if s.id == semester.id { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                                    }
                                }
                                Divider()
                                Button(.firstRunAddSemester) { addingSemester = true }
                            } label: {
                                ChipLabel(semester.title)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.plain).pointingHand()
                            .fixedSize()
                        }
                        ForEach(model.courses) { course in
                            CardRow {
                                CourseDot(color: model.accent(course.id).color).frame(width: Theme.Size.tile)
                                Text(course.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Spacer(minLength: Theme.Space.s)
                                Text(course.days).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                        CardRow(last: true) {
                            Button {
                                addingCourse = true
                            } label: {
                                Label(String(localized: .firstRunAddCourse), systemImage: "plus").font(Theme.Typeface.bodyStrong)
                            }
                            .buttonStyle(.pointing(.plain))
                            .foregroundStyle(Theme.Palette.chromeSelected)
                        }
                    } else {
                        FormRow(label: String(localized: .firstRunSemester), last: true) {
                            Button(.firstRunAddSemester) { addingSemester = true }
                        }
                    }
                }
            }
            Block(String(localized: .firstRunDay)) {
                Card {
                    FormRow(
                        label: String(localized: .firstRunDayBoundary), detail: String(localized: .firstRunDayBoundaryDetail), last: true
                    ) {
                        TimeMenu(minute: Bindable(model.settings).settings.dayBoundaryMinutes, hours: 0...8)
                    }
                }
            }
            .onChange(of: model.settings.settings.dayBoundaryMinutes) { model.dayBoundaryChanged() }
        }
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header(.firstRunStepProfile, .firstRunProfileSubtitle)
            ProfileCard(workspace: model.workspace)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header(.firstRunStepPermissions, .firstRunPermissionsSubtitle)
            Card {
                let all = SystemPermission.allCases
                ForEach(Array(all.enumerated()), id: \.element) { i, permission in
                    FormRow(
                        label: String(localized: permission.title), detail: String(localized: permission.detail), last: i == all.count - 1
                    ) {
                        switch model.state(of: permission) {
                        case .allowed:
                            Label(String(localized: .firstRunAllowed), systemImage: "checkmark")
                                .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.success)
                        case .denied:
                            Button(.firstRunOpenSettings) { if let url = permission.settingsURL { openURL(url) } }
                        case .unknown:
                            Button(.firstRunAllow) { Task { await model.request(permission) } }
                        }
                    }
                }
            }
        }
    }

    private var claude: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            header(.firstRunStepClaude, .firstRunClaudeSubtitle)
            ClaudeConnectionCard(model: model.settings)
        }
    }

    private func reconnect(_ trouble: FolderTrouble) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            switch trouble {
            case .missing(let path):
                header(model.waiting ? .firstRunStepFolder : .firstRunReconnectTitle, .firstRunMissingSubtitle)
                NoticeCard(title: String(localized: .firstRunMissingBanner), systemImage: "exclamationmark.triangle.fill") {
                    Button(.firstRunFindAgain) { model.findAgain() }
                } rows: {
                    CardRow(last: true) {
                        icon("folder"); placeText(path)
                    }
                }
            case .downloading(let path, let done, let total):
                let fraction = FolderAvailability.downloading(done: done, total: total).fraction
                header(model.waiting ? .firstRunStepFolder : .firstRunReconnectTitle, .firstRunDownloadingSubtitle)
                NoticeCard(title: String(localized: .firstRunDownloadingBanner), systemImage: "icloud.and.arrow.down", informs: true) {
                    Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(Theme.Palette.info)
                } rows: {
                    CardRow {
                        icon("folder"); placeText(path)
                    }
                    CardRow(last: true) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            ProgressView(value: fraction)
                            Text(.firstRunDownloadedFiles(done, total)).font(Theme.Typeface.caption).monospacedDigit()
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .padding(.leading, Theme.Size.tile + Theme.Space.m)
                    }
                }
            }
            Block(String(localized: .firstRunOtherFolder)) {
                VStack(spacing: Theme.Space.m) {
                    option(.existing, detail: .firstRunMissingExistingDetail)
                    option(.fresh, detail: .firstRunFreshDetail)
                }
            }
        }
    }

    private func placeText(_ path: String) -> some View {
        Text(path).font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
    }
}

extension FirstRunStep {
    var title: LocalizedStringResource {
        switch self {
        case .welcome: .firstRunStepWelcome
        case .folder: .firstRunStepFolder
        case .term: .firstRunStepTerm
        case .profile: .firstRunStepProfile
        case .permissions: .firstRunStepPermissions
        case .claude: .firstRunStepClaude
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "info.circle"
        case .folder: "folder"
        case .term: "book.closed"
        case .profile: "person"
        case .permissions: "bell"
        case .claude: "sparkle"
        }
    }
}

extension SystemPermission {
    var title: LocalizedStringResource {
        switch self {
        case .notifications: .firstRunNotifications
        case .microphone: .firstRunMicrophone
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .notifications: .firstRunNotificationsDetail
        case .microphone: .firstRunMicrophoneDetail
        }
    }
}
