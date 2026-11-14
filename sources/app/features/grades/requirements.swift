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

struct RequirementLine: View {
    let category: RequirementCategory
    let credits: CategoryCredits
    let header: Bool
    var title: String?

    var body: some View {
        let s = RequirementStatus(category: category, credits: credits)
        let idle = s.goal == nil && s.done + s.taking == 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title ?? category.name)
                        .font(header ? Theme.Typeface.figureSmall : Theme.Typeface.body)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                        .lineLimit(1)
                    if let note = Self.note(category, s) {
                        Text(note).font(Theme.Typeface.caption).foregroundStyle(s.over ? Theme.Palette.warning : Theme.Palette.textTertiary)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(s.done.formatted()).font(header ? Theme.Typeface.figureSmall : Theme.Typeface.bodyStrong)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let goal = s.goal { Text("/ \(goal.formatted())").foregroundStyle(Theme.Palette.textTertiary) }
                    Text(Self.unit(s)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .monospacedDigit()
                ProgressRing(done: s.done, taking: s.taking, goal: s.goal, met: s.met, over: s.over)
            }
            if header, s.goal != nil {
                CreditBar(credits: CategoryCredits(earned: s.done, inProgress: s.taking), goal: s.goal, met: s.met, height: 6)
            }
        }
    }

    static func unit(_ s: RequirementStatus) -> String {
        String(localized: s.countsCourses ? .requirementsUnitCourses : .requirementsUnitCredits)
    }

    static func note(_ category: RequirementCategory, _ s: RequirementStatus) -> String? {
        var parts: [String] = []
        if s.taking > 0 { parts.append(String(localized: .requirementsTaking(s.taking.formatted()))) }
        if s.over, let cap = category.maxCredits {
            parts.append(String(localized: .requirementsCapExceeded(cap.formatted())))
        } else if let goal = s.goal, !s.met {
            parts.append(String(localized: .requirementsLeft((goal - s.done).formatted(), unit(s))))
        } else if let cap = category.maxCredits, cap > 0, cap != category.minCredits {
            parts.append(String(localized: .requirementsCap(cap.formatted())))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct ProgressRing: View {
    let done: Double
    let taking: Double
    let goal: Double?
    let met: Bool
    let over: Bool

    var body: some View {
        Group {
            if over {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.Palette.warning)
            } else if met {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
            } else if let goal {
                ZStack {
                    Circle().stroke(Theme.Palette.fill, lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, (done + taking) / goal)).stroke(
                        Theme.Palette.textTertiary.opacity(0.45), lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, done / goal)).stroke(
                        Theme.Palette.textSecondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .rotationEffect(.degrees(-90))
                .padding(2)
            } else {
                Color.clear
            }
        }
        .font(Theme.Glyph.check)
        .frame(width: 16, height: 16)
    }
}

struct CreditBar: View {
    let credits: CategoryCredits
    let goal: Double?
    let met: Bool
    var height: CGFloat = 6

    var body: some View {
        let scale = max(goal ?? 0, credits.earned + credits.inProgress, 1)
        let color = met ? Theme.Palette.success : Theme.Palette.textSecondary
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.fill)
                Capsule().fill(color.opacity(Theme.Opacity.projected)).frame(
                    width: w * min(1, (credits.earned + credits.inProgress) / scale))
                Capsule().fill(color).frame(width: w * min(1, credits.earned / scale))
            }
        }
        .frame(height: height)
    }
}

struct RequirementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: RequirementEditModel
    @State private var removing = false

    init(workspace: Workspace, category: RequirementCategory) {
        _model = State(initialValue: RequirementEditModel(workspace: workspace, category: category))
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: String(localized: .commonSave), disabled: model.draft.name.isEmpty, carded: false, width: 560,
            deleteTitle: model.isNew ? nil : String(localized: .requirementsRemove), onDelete: { removing = true }
        ) {
            Block(String(localized: .requirementsFieldCategory)) {
                Card {
                    FormRow(label: String(localized: .requirementsFieldName)) {
                        InlineField(String(localized: .requirementsFieldNameExample), text: $model.draft.name)
                    }
                    FormRow(label: String(localized: .requirementsFieldGroup), detail: String(localized: .requirementsFieldGroupDetail)) {
                        InlineField(String(localized: .requirementsFieldGroupExample), text: $model.draft.group)
                    }
                    FormRow(label: String(localized: .requirementsFieldParent)) {
                        SearchSelect(selection: $model.draft.parentId, options: model.parentOptions)
                    }
                    FormRow(label: String(localized: .requirementsFieldProgram), detail: String(localized: .requirementsFieldProgramDetail))
                    {
                        ChoiceMenu(selection: $model.draft.programId, options: model.programOptions)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMajor), detail: String(localized: .requirementsFieldMajorDetail),
                        last: true
                    ) { Switch(isOn: $model.draft.isMajor) }
                }
            }
            Block(String(localized: .requirementsCriteria), note: String(localized: .requirementsCriteriaNote)) {
                Card {
                    FormRow(label: String(localized: .requirementsFieldMinCredits)) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.minCredits, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMaxCredits),
                        detail: String(localized: .requirementsFieldMaxCreditsDetail)
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.maxCredits, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMinCount), detail: String(localized: .requirementsFieldMinCountDetail)
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.minCount, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldSharedCap), detail: String(localized: .requirementsFieldSharedCapDetail),
                        last: true
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.maxSharedCredits, format: .number).pill(
                            width: 72)
                    }
                }
            }
            FormTextArea(
                label: String(localized: .requirementsFieldRule),
                text: Binding(get: { model.draft.rule ?? "" }, set: { model.draft.rule = $0.isEmpty ? nil : $0 }))
        } onConfirm: {
            model.confirm()
            dismiss()
        }
        .confirmationDialog(RequirementsModel.removeTitle(model.draft), isPresented: $removing) {
            Button(.commonDelete, role: .destructive) {
                model.remove()
                dismiss()
            }
        } message: {
            Text(.requirementsRemoveMessage)
        }
    }
}

struct CategoryMenu: View {
    // 과목 편집기가 넘길 workspace 없이 이 메뉴를 만들므로 environment에서 읽는다.
    @Environment(Workspace.self) private var workspace
    @Binding var selection: [UUID]
    var course: Course?

    var body: some View {
        SearchMultiSelect(
            selection: $selection,
            options: RequirementsModel.categoryOptions(workspace.requirementCatalog, selection: selection, course: course),
            placeholder: String(localized: .requirementsPickCategory))
    }
}

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(.requirementsProfile).font(Theme.Typeface.columnTitle)
            ProfileCard(workspace: workspace)
            Text(.profileNote).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.m)
            HStack {
                Spacer()
                Button(.commonClose) { dismiss() }.buttonStyle(.prominent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }
}

struct ProfileCard: View {
    @State private var model: ProfileModel

    init(workspace: Workspace) {
        _model = State(initialValue: ProfileModel(workspace: workspace))
    }

    var body: some View {
        let rule = model.rule
        let options = model.codeOptions
        Card {
            FormRow(label: String(localized: .profileEmail)) {
                InlineField("name@gm.gist.ac.kr", text: $model.email)
            }
            FormRow(label: String(localized: .profileAdmissionYear)) {
                TextField(
                    String(localized: .profileAdmissionYearExample),
                    value: Binding(get: { rule.admissionYear }, set: { y in model.update { $0.admissionYear = y } }),
                    format: .number.grouping(.never)
                )
                .pill(width: 72)
            }
            // 같은 과정이 두 번 나열되면 충돌하므로 위치로 구분한다.
            ForEach(Array(rule.programs.enumerated()), id: \.offset) { i, p in
                FormRow(label: String(localized: .profileProgram(i + 1))) {
                    SearchSelect(
                        selection: Binding(get: { p.codeId }, set: { id in model.update { $0.programs[i].codeId = id } }), options: options)
                    ChoiceMenu(
                        selection: Binding(get: { p.kind }, set: { k in model.update { $0.programs[i].kind = k } }),
                        options: StudentProgram.Kind.allCases.map { ($0, $0.label) })
                    Button(.profileRemoveProgram, systemImage: "minus.circle") { model.update { $0.programs.remove(at: i) } }
                        .buttonStyle(.ghostIcon)
                }
                .contextMenu { Button(.profileRemoveProgramMenu, role: .destructive) { model.update { $0.programs.remove(at: i) } } }
            }
            CardRow(last: true) {
                SearchPicker(options: model.addableOptions, pick: { model.addProgram($0) }, prompt: String(localized: .profileCodeSearch)) {
                    Label(.profileAddProgram, systemImage: "plus")
                }
                Spacer()
            }
        }
        .onAppear { model.load() }
        // 저장할 때마다 transcript.json을 다시 쓰므로, 설정처럼 입력이 멈춘 뒤 저장한다.
        .task(id: model.email) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.saveEmail()
        }
    }
}
