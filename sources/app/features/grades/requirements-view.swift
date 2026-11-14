import FolioDomain
import SwiftUI

struct RequirementsView: View {
    @State private var model: RequirementsModel
    @Environment(\.openLink) private var openLink
    @State private var editingProfile = false

    init(workspace: Workspace) {
        _model = State(initialValue: RequirementsModel(workspace: workspace))
    }

    func openCourse(_ course: Course) { openLink(.course(course.id)) }

    var body: some View {
        let audit = model.audit
        let (suggestions, overShared, unallowed, unassigned) = (audit.suggestions, audit.overShared, audit.unallowed, audit.unassigned)
        let credits = model.credits
        let listed = model.listed

        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .requirementsTitle), subtitle: model.subtitle)
                Spacer()
                Button(.requirementsProfile, systemImage: "person.crop.circle") { editingProfile = true }
                    .buttonStyle(.ghost)
                Button(.requirementsAddCategory, systemImage: "plus") { model.addCategory() }
                    .buttonStyle(.ghost)
            }

            if !suggestions.isEmpty {
                let refusals = model.acceptRefusals(suggestions)
                NoticeCard(
                    title: model.suggestionsTitle(suggestions.count), detail: String(localized: .requirementsSuggestionsDetail),
                    trailing: {
                        if suggestions.count > 1 {
                            Button(.requirementsApplyAll) { model.accept(suggestions) }.buttonStyle(.ghost)
                                .disabled(refusals.all != nil).help(refusals.all ?? "")
                        }
                    }
                ) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, s in
                        let course = model.course(s.courseId)
                        let refusal = refusals.rows[s.courseId]
                        CardRow(last: i == suggestions.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(course?.title ?? "").font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Text(model.suggestionSource(s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            Text(model.suggestionChange(s))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
                                .multilineTextAlignment(.trailing)
                            Button(.requirementsApply) { model.accept([s]) }.buttonStyle(.ghost)
                                .disabled(refusal != nil).help(refusal ?? "")
                        }
                        .contextMenu {
                            Button(.requirementsApply) { model.accept([s]) }.disabled(refusal != nil)
                            if let course { Button(.commonOpenCourse) { openCourse(course) } }
                        }
                    }
                }
            }
            ForEach(overShared, id: \.categoryId) { s in
                NoticeCard(title: model.overSharedTitle(s), detail: model.overSharedDetail(s), trailing: { EmptyView() }) {
                    ForEach(Array(s.courses.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == s.courses.count - 1) {
                            courseLabel(course)
                            Spacer(minLength: Theme.Space.m)
                            categoryMenu(course)
                        }
                        .contextMenu { Button(.commonOpenCourse) { openCourse(course) } }
                    }
                }
            }
            ForEach(unallowed, id: \.categoryId) { s in
                NoticeCard(title: model.unallowedTitle(s), detail: model.unallowedDetail(s), trailing: { EmptyView() }) {
                    ForEach(Array(s.unallowed.enumerated()), id: \.element.id) { i, course in
                        let refusal = model.approvalRefusal(course.id)
                        CardRow(last: i == s.unallowed.count - 1) {
                            courseLabel(course)
                            Spacer(minLength: Theme.Space.m)
                            categoryMenu(course)
                            Button(.requirementsApproveSharing) { model.approveSharing(course.id) }.buttonStyle(.ghost)
                                .disabled(refusal != nil).help(refusal ?? "")
                        }
                        .contextMenu {
                            Button(.requirementsApproveSharingMenu) { model.approveSharing(course.id) }.disabled(refusal != nil)
                            Button(.commonOpenCourse) { openCourse(course) }
                        }
                    }
                }
            }
            if !unassigned.isEmpty {
                NoticeCard(
                    title: model.unassignedTitle(unassigned.count), detail: String(localized: .requirementsUnassignedDetail),
                    trailing: { EmptyView() }
                ) {
                    ForEach(Array(unassigned.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == unassigned.count - 1) {
                            courseLabel(course, showsTaking: false)
                            Spacer(minLength: Theme.Space.m)
                            categoryMenu(course)
                        }
                        .contextMenu { Button(.commonOpenCourse) { openCourse(course) } }
                    }
                }
            }

            StatStrip(items: model.stats)

            if model.catalog.categories.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .requirementsEmpty)) } }
            }
            let cards = model.cards
            let columns = model.columns
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    ForEach(columns.indices, id: \.self) { c in
                        VStack(spacing: Theme.Space.l) {
                            ForEach(columns[c], id: \.group) { groupCard($0, credits: credits, listed: listed) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(minWidth: 720)
                VStack(spacing: Theme.Space.l) { ForEach(cards, id: \.group) { groupCard($0, credits: credits, listed: listed) } }
            }

            if model.showsHandbookNote {
                Block(title: String(localized: .requirementsHandbookTitle), note: model.handbookNote, trailing: { EmptyView() }) {
                    Card { CardRow(last: true) { EmptyLine(String(localized: .requirementsHandbookAllMatch)) } }
                }
            }
        }
        .navigationTitle(.requirementsTitle)
        .confirmationDialog(
            model.removing.map(RequirementsModel.removeTitle) ?? "",
            isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }),
            presenting: model.removing
        ) { c in
            Button(.commonDelete, role: .destructive) { RequirementsModel.remove(c, in: model.workspace) }
        } message: { _ in
            Text(.requirementsRemoveMessage)
        }
        .sheet(item: $model.editing) { RequirementSheet(workspace: model.workspace, category: $0) }
        .sheet(isPresented: $editingProfile) { ProfileSheet(workspace: model.workspace) }
        .confirming($model.pending)
    }

    func courseLabel(_ course: Course, showsTaking: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(course.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
            Text(model.courseDetail(course, showsTaking: showsTaking))
                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    func categoryMenu(_ course: Course) -> some View {
        CategoryMenu(selection: Binding(get: { course.categoryIds }, set: { model.setCategories(course.id, $0) }), course: course)
    }

    func groupCard(_ card: RequirementsModel.GroupCard, credits: [UUID: CategoryCredits], listed: [UUID: [Course]]) -> some View {
        let header = RequirementsModel.header(of: card)
        let body = card.rows.filter { $0.category.id != header?.category.id }
        let lift = header == nil ? 0 : 1
        return Card {
            Group {
                if let header {
                    VStack(alignment: .leading, spacing: 0) {
                        toggle(header.category, listed[header.category.id] ?? []) {
                            RequirementLine(
                                category: header.category, credits: credits[header.category.id] ?? .init(), header: true,
                                title: card.group.isEmpty ? nil : card.group
                            ).contentShape(.rect)
                        }
                    }
                } else {
                    Text(RequirementsModel.groupTitle(card.group)).font(Theme.Typeface.figureSmall).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.l)
            .padding(.bottom, Theme.Space.s)
            ForEach(body, id: \.category.id) { row in
                VStack(alignment: .leading, spacing: 0) {
                    toggle(row.category, listed[row.category.id] ?? []) {
                        RequirementLine(category: row.category, credits: credits[row.category.id] ?? .init(), header: false)
                            .padding(.vertical, Theme.Space.s)
                            .contentShape(.rect)
                    }
                }
                .padding(.leading, CGFloat(max(0, row.depth - lift)) * Theme.Space.l)
                .padding(.horizontal, Theme.Space.l)
            }
            Spacer().frame(height: Theme.Space.s)
        }
    }

    func toggle(_ category: RequirementCategory, _ courses: [Course], @ViewBuilder label: () -> some View) -> some View {
        Button {
            model.showing = category.id
        } label: {
            label()
        }
        .buttonStyle(.pointing(.plain))
        .popover(
            isPresented: Binding(
                get: { model.showing == category.id }, set: { if !$0, model.showing == category.id { model.showing = nil } }),
            arrowEdge: .bottom
        ) { courseList(category, courses) }
        .contextMenu {
            ItemMenu(
                source: RequirementMenuSource(
                    show: { model.showing = category.id }, edit: { model.editing = category },
                    remove: { model.removing = category }))
        }
        .help(category.rule ?? String(localized: .requirementsShowCoursesHelp))
    }

    func courseList(_ category: RequirementCategory, _ courses: [Course]) -> some View {
        let sorted = model.sortedForList(courses)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(category.name).font(Theme.Typeface.bodyStrong)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if sorted.isEmpty { Text(.requirementsNoCourses).foregroundStyle(Theme.Palette.textTertiary) }
                    ForEach(sorted) { course in
                        Button {
                            model.showing = nil; openCourse(course)
                        } label: {
                            HStack(spacing: Theme.Space.s) {
                                CourseMark(model.workspace, course.id, inline: true)
                                Text(course.title).lineLimit(1)
                                if course.finalGrade == nil { Text(.gradesEnrolled).foregroundStyle(Theme.Palette.warning) }
                                Spacer(minLength: Theme.Space.s)
                                Text(model.listDetail(course))
                                    .foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                            }.contentShape(.rect)
                        }
                        .buttonStyle(.pointing(.plain))
                        .contextMenu {
                            Button(.commonOpenCourse) {
                                model.showing = nil; openCourse(course)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .overflowFade(.vertical)
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            // popover가 화면에 있는 동안에는 시트를 열 수 없으므로 popover를 먼저 닫는다.
            Button(.requirementsEdit) {
                model.showing = nil; model.editing = category
            }.buttonStyle(.ghost).padding(.top, 2)
        }
        .font(Theme.Typeface.caption)
        .padding(Theme.Space.m)
        .frame(width: 340, alignment: .leading)
    }
}
