import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

/// Edits course.json. The folder name follows the title, main code and number, so saving a change to those renames it.
struct EditCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        let course = model.course
        SheetForm(title: String(localized: .courseEdit), confirm: String(localized: .commonSave), disabled: !model.canSave,
                  note: model.note, carded: false, width: 600) {
            Block(String(localized: .courseEditCourse)) {
                Card {
                    FormRow(label: String(localized: .courseEditName)) { InlineField(String(localized: .courseEditNameExample), text: $model.title) }
                    // Prefix and number side by side, as the course reads: GS2004-02.
                    FormRow(label: String(localized: .courseEditCode), detail: model.codeDetail) {
                        CodesMenu(codes: $model.codes)
                        TextField("2004-02", text: $model.number).pill(width: 100)
                    }
                    if model.codes.count > 1 {
                        FormRow(label: String(localized: .courseEditMainCode)) {
                            ChoiceMenu(selection: Binding(get: { model.codes[0] }, set: model.makeMain), options: model.codeOptions)
                        }
                    }
                    FormRow(label: String(localized: .courseEditCredits)) { CreditsField(credits: $model.credits) }
                    FormRow(label: String(localized: .courseEditGrading), last: true) {
                        ChoiceMenu(selection: $model.mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
                    }
                }
            }
            ClassTimesBlock(schedule: $model.schedule)
            Block(String(localized: .courseEditManage)) {
                Card {
                    FormRow(label: String(localized: .courseInfoPeople)) {
                        SearchMultiSelect(selection: $model.people, options: model.peopleOptions, placeholder: model.peoplePlaceholder)
                    }
                    FormRow(label: String(localized: .courseEditCategories), detail: String(localized: .courseEditCategoriesDetail)) {
                        CategoryMenu(selection: $model.categories, course: model.draft)
                    }
                    if model.showsSharing {
                        FormRow(label: String(localized: .courseEditSharing), detail: String(localized: .courseEditSharingDetail)) { Switch(isOn: $model.sharingApproved) }
                    }
                    FormRow(label: String(localized: .courseEditReviews), detail: String(localized: .courseEditReviewsDetail)) { Switch(isOn: $model.reviews) }
                    FormRow(label: String(localized: .courseEditIcon), detail: String(localized: .courseEditIconDetail)) {
                        CourseIconPicker(icon: $model.icon, color: model.workspace.accent(course.id, token: model.color).color)
                    }
                    FormRow(label: String(localized: .courseEditColor), last: true) {
                        HStack(spacing: Theme.Space.s) {
                            if model.color.isEmpty {
                                Text(.courseEditColorAuto).foregroundStyle(Theme.Palette.textTertiary)
                            } else {
                                Button(.courseEditColorMakeAuto) { model.color = "" }.buttonStyle(.ghost)
                            }
                            CourseColorSwatches(token: $model.color)
                        }
                    }
                }
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
    }
}

/// Only the presets are offered, so every course keeps the palette's tested contrast and follows it when it changes.
struct CourseColorSwatches: View {
    @Binding var token: String

    static let names: [String: LocalizedStringResource] = [
        "violet": .courseColorViolet, "blue": .courseColorBlue, "orange": .courseColorOrange, "green": .courseColorGreen,
        "pink": .courseColorPink, "olive": .courseColorOlive, "teal": .courseColorTeal, "red": .courseColorRed,
        "graphite": .courseColorGraphite,
    ]

    var body: some View {
        // A #RRGGBB saved before shows on the preset it now reads as.
        let chosen = token.isEmpty ? nil : CourseColor.token(token, position: 0)
        HStack(spacing: Theme.Space.xs) {
            ForEach(CourseAccent.presets, id: \.name) { preset in
                let on = preset.name == chosen
                let name = Self.names[preset.name].map { String(localized: $0) } ?? preset.name
                Button { token = preset.name } label: {
                    Circle().fill(preset.accent.color)
                        .frame(width: Theme.Size.tile, height: Theme.Size.tile)
                        .padding(Theme.Space.xxs)
                        .overlay { if on { Circle().strokeBorder(Theme.Palette.text, lineWidth: 1.5) } }
                        .contentShape(.circle)
                }
                .buttonStyle(.pointing(.plain))
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// The next lecture is suggested from these.
struct ClassTimesBlock: View {
    @Binding var schedule: [ClassTime]

    var body: some View {
        Block(title: String(localized: .classTimesTitle), note: String(localized: .classTimesNote), trailing: {
            Button(.classTimesAdd, systemImage: "plus") { schedule.append(ClassTime(weekday: 1, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)) }
                .buttonStyle(.ghost)
        }) {
            Card {
                if schedule.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .classTimesEmpty)) } }
                ForEach(schedule.indices, id: \.self) { i in
                    let slot = schedule[i]
                    CardRow(last: i == schedule.count - 1) {
                        ChoiceMenu(selection: $schedule.element(at: i, fallback: slot).weekday,
                                   options: (1...7).map { ($0, String(localized: .classTimesWeekday(ClassTime.weekdayNames[$0 - 1]))) })
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).startMinute)
                        Text("–").foregroundStyle(Theme.Palette.textTertiary)
                        TimeMenu(minute: $schedule.element(at: i, fallback: slot).endMinute)
                        Spacer(minLength: Theme.Space.m)
                        TextField(String(localized: .classTimesRoom), text: $schedule.element(at: i, fallback: slot).room).pill(width: 112)
                        ClassLinkButton(link: $schedule.element(at: i, fallback: slot).link)
                        Button(.commonDelete, systemImage: "minus.circle") { schedule.remove(at: i) }
                            .buttonStyle(.ghostIcon).tint(Theme.Palette.danger)
                    }
                }
            }
        }
    }
}

/// A class time's meeting link, for a course held online every week. In a popover, since most slots have none and the
/// row has no room for a second field.
struct ClassLinkButton: View {
    @Binding var link: String?
    @State private var open = false

    var body: some View {
        let has = !(link ?? "").isEmpty
        Button(String(localized: .classTimesLink), systemImage: has ? "video.fill" : "video") { open = true }
            .buttonStyle(.ghostIcon)
            .tint(has ? Theme.Palette.text : Theme.Palette.textTertiary)
            .help(link.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: .classTimesLinkHelp))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(.classTimesLink).font(Theme.Typeface.bodyStrong)
                    TextField(String(localized: .classTimesLinkPrompt), text: Binding(get: { link ?? "" }, set: { link = OnlineLink.stored($0) }))
                        .pill(width: 288)
                    Text(.classTimesLinkHelp).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(Theme.Space.l)
                .frame(width: 320)
            }
    }
}

/// Only the class times, for the sessions page.
struct ClassTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        // The course as the heading: the block below already says 수업 시간, and twice in a row read as a mistake.
        SheetForm(title: model.course.title, confirm: String(localized: .commonSave), disabled: model.timesNote != nil,
                  note: model.timesNote, carded: false, width: 600) {
            ClassTimesBlock(schedule: $model.schedule)
        } onConfirm: {
            model.confirmSchedule()
            dismiss()
        }
    }
}

/// Credits as a typed number; half credits exist, so a fixed menu of whole numbers won't do.
struct CreditsField: View {
    @Binding var credits: Double?

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("3", value: $credits, format: .number).pill(width: 56).multilineTextAlignment(.trailing)
            Text(.courseEditCredits).foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// Cross-listed codes in order; the first is the main code.
struct CodesMenu: View {
    @Environment(Workspace.self) private var workspace
    @Binding var codes: [UUID]

    var body: some View {
        let all = workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
        SearchMultiSelect(selection: $codes, options: all.map { PickOption(id: $0.id, title: "\($0.prefix) · \($0.department)", detail: $0.program) },
                          summary: codes.isEmpty ? nil : codes.compactMap { id in all.first { $0.id == id }?.prefix }.joined(separator: " · "))
    }
}
