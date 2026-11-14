import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct EditCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: EditCourseModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: EditCourseModel(workspace: workspace, course: course))
    }

    var body: some View {
        let course = model.course
        SheetForm(
            title: String(localized: .courseEdit), confirm: String(localized: .commonSave), disabled: !model.canSave,
            note: model.note, carded: false, width: 600
        ) {
            Block(String(localized: .courseEditCourse)) {
                Card {
                    FormRow(label: String(localized: .courseEditName)) {
                        InlineField(String(localized: .courseEditNameExample), text: $model.title)
                    }
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
                        FormRow(label: String(localized: .courseEditSharing), detail: String(localized: .courseEditSharingDetail)) {
                            Switch(isOn: $model.sharingApproved)
                        }
                    }
                    FormRow(label: String(localized: .courseEditReviews), detail: String(localized: .courseEditReviewsDetail)) {
                        Switch(isOn: $model.reviews)
                    }
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
