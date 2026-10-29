import Algorithms
import FolioDomain
import SwiftUI

typealias RequirementCategory = FolioDomain.Category

/// docs/SPEC.md "졸업 요건": degree totals, the category tree with progress, and courses still without a category.
struct RequirementsView: View {
    @Environment(Workspace.self) private var workspace
    let openCourse: (Course) -> Void
    @State private var editing: RequirementCategory?
    @State private var editingProfile = false
    @State private var removing: RequirementCategory?
    /// The category whose courses are showing in a popover.
    @State private var showing: UUID?

    var body: some View {
        let catalog = workspace.requirementCatalog
        let courses = workspace.allCourseRecords
        let rule = workspace.transcript.graduation
        let progress = GPACalculator.graduation(semesters: workspace.transcript.semesters, courses: courses, catalog: catalog)
        let gpa = GPACalculator.cumulative(semesters: workspace.transcript.semesters, courses: courses, catalog: catalog).gpa
        let credits = GPACalculator.categoryCredits(courses: courses, catalog: catalog)
        let listed = GPACalculator.categoryCourses(courses: courses, catalog: catalog)
        let audit = RequirementAudit(courses: courses, semesters: workspace.transcript.semesters, catalog: catalog)
        let (suggestions, overShared, unallowed, unassigned) = (audit.suggestions, audit.overShared, audit.unallowed, audit.unassigned)

        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "졸업 요건", subtitle: profileLine(rule) ?? "학사편람에서 옮겨 적은 요건입니다. 항목을 누르면 고칩니다")
                Spacer()
                Button("내 정보", systemImage: "person.crop.circle") { editingProfile = true }
                    .buttonStyle(.ghost)
                Button("분류 추가", systemImage: "plus") {
                    editing = RequirementCategory(device: workspace.device, at: .now, name: "")
                }
                .buttonStyle(.ghost)
            }

            // What needs a decision sits up here with its own buttons, where it's seen, not in a list at the bottom.
            if !suggestions.isEmpty {
                NoticeCard(title: "학사편람과 분류가 다른 과목 \(suggestions.count)개", detail: "과목을 들은 해의 편람과 다르게 분류되어 있습니다", trailing: {
                    if suggestions.count > 1 {
                        Button("모두 적용") { for s in suggestions { workspace.setCategories(s.courseId, s.categoryIds) } }.buttonStyle(.ghost)
                    }
                }) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { i, s in
                        let course = courses.first { $0.id == s.courseId }
                        CardRow(last: i == suggestions.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(course?.title ?? "").font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Text("\(s.code) · \(String(s.year)) 편람").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            Text(names(course?.categoryIds ?? [], in: catalog) + " → " + names(s.categoryIds, in: catalog))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).lineLimit(2).multilineTextAlignment(.trailing)
                            Button("적용") { workspace.setCategories(s.courseId, s.categoryIds) }.buttonStyle(.ghost)
                        }
                        .contextMenu {
                            Button("적용") { workspace.setCategories(s.courseId, s.categoryIds) }
                            if let course { Button("과목 열기") { openCourse(course) } }
                        }
                    }
                }
            }
            ForEach(overShared, id: \.categoryId) { s in
                let name = catalog.category(s.categoryId)?.name ?? ""
                NoticeCard(title: "‘\(name)’ 이중 계산 \((s.earned + s.inProgress).formatted())학점 중 \(s.cap.formatted())학점만 인정",
                           detail: "넘는 만큼은 \(name)에서 빼고 셉니다. 이중 계산하지 않을 과목을 한쪽 분류에서 빼세요", trailing: { EmptyView() }) {
                    ForEach(Array(s.courses.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == s.courses.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(course.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Text([workspace.semester(of: course)?.title, "\(course.credits.formatted())학점", course.finalGrade == nil ? "수강 중" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            CategoryMenu(selection: Binding(get: { course.categoryIds }, set: { workspace.setCategories(course.id, $0) }), course: course)
                        }
                        .contextMenu { Button("과목 열기") { openCourse(course) } }
                    }
                }
            }
            ForEach(unallowed, id: \.categoryId) { s in
                let name = catalog.category(s.categoryId)?.name ?? ""
                NoticeCard(title: "‘\(name)’에 함께 셀 수 없는 과목 \(s.unallowed.count)개",
                           detail: "강의 공유 과목도 학과 인정 과목도 아니어서 \(name)에서 빼고 셉니다. 한쪽 분류에서 빼거나, 학과가 인정한 과목이면 표시하세요",
                           trailing: { EmptyView() }) {
                    ForEach(Array(s.unallowed.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == s.unallowed.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(course.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Text([workspace.semester(of: course)?.title, "\(course.credits.formatted())학점", course.finalGrade == nil ? "수강 중" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            CategoryMenu(selection: Binding(get: { course.categoryIds }, set: { workspace.setCategories(course.id, $0) }), course: course)
                            Button("학과 인정") { workspace.approveSharing(course.id) }.buttonStyle(.ghost)
                        }
                        .contextMenu {
                            Button("학과 인정 과목으로 표시") { workspace.approveSharing(course.id) }
                            Button("과목 열기") { openCourse(course) }
                        }
                    }
                }
            }
            if !unassigned.isEmpty {
                NoticeCard(title: "분류 없는 과목 \(unassigned.count)개", detail: "분류를 정해야 요건에 들어갑니다", trailing: { EmptyView() }) {
                    ForEach(Array(unassigned.enumerated()), id: \.element.id) { i, course in
                        CardRow(last: i == unassigned.count - 1) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text(course.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                Text([workspace.semester(of: course)?.title, "\(course.credits.formatted())학점"].compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: Theme.Space.m)
                            CategoryMenu(selection: Binding(get: { course.categoryIds }, set: { workspace.setCategories(course.id, $0) }), course: course)
                        }
                        .contextMenu { Button("과목 열기") { openCourse(course) } }
                    }
                }
            }

            StatStrip(items: [
                .init(title: "졸업 학점", value: "\(progress.counted.formatted()) / \(rule.totalCredits.formatted())",
                      detail: [progress.inProgress > 0 ? "수강 중 \(progress.inProgress.formatted())" : nil,
                               progress.earned > progress.counted ? "상한 초과 \((progress.earned - progress.counted).formatted()) 제외" : nil]
                          .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                      tone: progress.counted >= rule.totalCredits ? .success : .plain),
                .init(title: "남은 학점", value: "\(max(0, rule.totalCredits - progress.counted - progress.inProgress).formatted())",
                      detail: "수강 중 과목을 모두 이수하면"),
                .init(title: "평점", value: GPACalculator.label(gpa), detail: String(format: "하한 %.1f", rule.minGPA),
                      tone: (gpa ?? 0) >= rule.minGPA ? .plain : .danger, sensitive: true),
                // A detail on every item keeps the figures on one line across the strip.
                .init(title: "분류 없는 과목", value: "\(unassigned.count)", detail: unassigned.isEmpty ? "모두 분류됨" : "위에서 분류를 정합니다",
                      tone: unassigned.isEmpty ? .plain : .warning),
            ])

            if catalog.categories.isEmpty {
                Card { CardRow(last: true) { EmptyLine("세부 분류가 없습니다") } }
            }
            let cards = Self.groups(catalog.categories).map { group in (group, Self.tree(catalog.categories).filter { $0.group == group }) }
            // Largest first so the long 기초‧교양 card anchors a column and the small ones fill the other.
            let columns = Self.balance(cards.sorted { $0.1.count > $1.1.count }, by: \.1.count)
            // Two columns keep each card narrow; ViewThatFits drops to one when the window is too narrow for both.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.l) {
                    ForEach(columns.indices, id: \.self) { c in
                        VStack(spacing: Theme.Space.l) { ForEach(columns[c], id: \.0) { groupCard($0.0, rows: $0.1, credits: credits, listed: listed) } }
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(minWidth: 720)
                VStack(spacing: Theme.Space.l) { ForEach(cards, id: \.0) { groupCard($0.0, rows: $0.1, credits: credits, listed: listed) } }
            }

            // Shown whenever a handbook is loaded, so the feature stays visible after every course is classified.
            if !catalog.handbooks.isEmpty && suggestions.isEmpty {
                Block(title: "학사편람 분류", note: catalog.handbooks.map { "\($0.year)" }.joined(separator: ", ") + " 편람 · 과목을 들은 해의 편람만 봅니다", trailing: { EmptyView() }) {
                    Card { CardRow(last: true) { EmptyLine("편람에 있는 과목은 모두 편람대로 분류되어 있습니다") } }
                }
            }
        }
        .navigationTitle("졸업 요건")
        .confirmationDialog(removing.map(RequirementSheet.removeTitle) ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { c in
            Button("삭제", role: .destructive) { RequirementSheet.remove(c, workspace: workspace) }
        } message: { _ in RequirementSheet.removeMessage }
        .sheet(item: $editing) { RequirementSheet(category: $0) }
        .sheet(isPresented: $editingProfile) { ProfileSheet() }
    }

    func names(_ ids: [UUID], in catalog: Catalog) -> String {
        let names = ids.compactMap { catalog.category($0)?.name }
        return names.isEmpty ? "없음" : names.joined(separator: ", ")
    }

    /// `2025학번 · EC 주전공 · AI 복수전공`
    func profileLine(_ rule: GraduationRule) -> String? {
        let parts = [rule.admissionYear.map { "\($0)학번" }]
            + rule.programs.map { workspace.programTitle($0) }
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// One card per group. A top-level category named like its group (기초‧교양) becomes the card's header, the only row
    /// with a bar; the rest show a figure and a small ring, so a card reads at a glance instead of as a stack of bars.
    func groupCard(_ group: String, rows: [(category: RequirementCategory, depth: Int, group: String)], credits: [UUID: CategoryCredits],
                   listed: [UUID: [Course]]) -> some View {
        let roots = rows.filter { $0.depth == 0 }
        // A group's total is its lone top-level category (전공 → 전공학점) or the one named like it (기초‧교양), so every
        // card that has one leads with it and its bar.
        let header = roots.count == 1 ? roots[0] : roots.first { $0.category.name == group }
        let body = rows.filter { $0.category.id != header?.category.id }
        let lift = header == nil ? 0 : 1
        return Card {
            Group {
                if let header {
                    VStack(alignment: .leading, spacing: 0) {
                        toggle(header.category, listed[header.category.id] ?? []) {
                            RequirementLine(category: header.category, credits: credits[header.category.id] ?? .init(), header: true,
                                            title: group.isEmpty ? nil : group).contentShape(.rect)
                        }
                    }
                } else {
                    Text(group.isEmpty ? "기타" : group).font(Theme.Typeface.figureSmall).frame(maxWidth: .infinity, alignment: .leading)
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

    /// A press shows the courses behind the figure in a popover, so the cards keep their place; editing the requirement
    /// is in the popover and the right-click menu.
    func toggle(_ category: RequirementCategory, _ courses: [Course], @ViewBuilder label: () -> some View) -> some View {
        Button { showing = category.id } label: { label() }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: Binding(get: { showing == category.id }, set: { if !$0, showing == category.id { showing = nil } }),
                 arrowEdge: .bottom) { courseList(category, courses) }
        .contextMenu {
            Button("과목 보기") { showing = category.id }
            Button("요건 편집…") { editing = category }
            Divider()
            Button("분류 삭제…", role: .destructive) { removing = category }
        }
        .help(category.rule ?? "눌러서 과목 보기")
    }

    /// The courses counted toward a category, oldest semester first; ones still being taken say so.
    func courseList(_ category: RequirementCategory, _ courses: [Course]) -> some View {
        let order = Dictionary(keepingFirst: workspace.transcript.semesters.map { ($0.id, $0.order) })
        let sorted = courses.sorted { (order[$0.semesterId ?? UUID()] ?? .max, $0.title) < (order[$1.semesterId ?? UUID()] ?? .max, $1.title) }
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(category.name).font(Theme.Typeface.bodyStrong)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if sorted.isEmpty { Text("아직 들어간 과목이 없습니다").foregroundStyle(Theme.Palette.textTertiary) }
                    ForEach(sorted) { course in
                        Button { showing = nil; openCourse(course) } label: { HStack(spacing: Theme.Space.s) {
                            CourseDot(color: workspace.accent(course.id).color, size: 6)
                            Text(course.title).lineLimit(1)
                            // Plain text, not a chip: a chip makes its row taller than the rest.
                            if course.finalGrade == nil { Text("수강 중").foregroundStyle(Theme.Palette.warning) }
                            Spacer(minLength: Theme.Space.s)
                            Text([workspace.semester(of: course)?.shortTitle, "\(course.credits.formatted())학점"].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                        }.contentShape(.rect) }
                        .buttonStyle(.pointing(.plain))
                        .contextMenu { Button("과목 열기") { showing = nil; openCourse(course) } }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            // The sheet can't open over a popover still on screen, so the popover closes first.
            Button("요건 편집") { showing = nil; editing = category }.buttonStyle(.ghost).padding(.top, 2)
        }
        .font(Theme.Typeface.caption)
        .padding(Theme.Space.m)
        .frame(width: 340, alignment: .leading)
    }

    /// Splits items into two columns, each going to the shorter column so far.
    static func balance<T>(_ items: [T], by weight: (T) -> Int) -> [[T]] {
        var columns: [[T]] = [[], []]
        var heights = [0, 0]
        for item in items {
            let c = heights[0] <= heights[1] ? 0 : 1
            columns[c].append(item)
            heights[c] += weight(item) + 2  // a card's header and padding weigh about two rows
        }
        return columns
    }

    /// Groups in the order their first top-level category appears.
    static func groups(_ categories: [RequirementCategory]) -> [String] {
        Array(categories.filter { $0.parentId == nil }.map(\.group).uniqued())
    }

    /// Parents before their children, depth first. A child takes its top-level ancestor's group so it stays under it.
    static func tree(_ categories: [RequirementCategory]) -> [(category: RequirementCategory, depth: Int, group: String)] {
        var result: [(RequirementCategory, Int, String)] = []
        func visit(_ c: RequirementCategory, depth: Int, group: String) {
            guard !result.contains(where: { $0.0.id == c.id }) else { return }
            result.append((c, depth, group))
            for child in categories where child.parentId == c.id { visit(child, depth: depth + 1, group: group) }
        }
        let ids = Set(categories.map(\.id))
        // A parent missing from the catalog makes its child a root rather than hiding it.
        for root in categories where root.parentId.map({ !ids.contains($0) }) ?? true { visit(root, depth: 0, group: root.group) }
        return result.map { (category: $0.0, depth: $0.1, group: $0.2) }
    }
}

/// A category's earned and in-progress credits (or passed courses) against its requirement: the name with a short
/// note under it, the figure, and a ring that turns into a check once met.
struct RequirementLine: View {
    let category: RequirementCategory
    let credits: CategoryCredits
    /// The card's top row: larger type and a bar under it.
    let header: Bool
    /// Shown instead of the name, for a category heading its group's card.
    var title: String?

    var counts: Bool { category.minCount != nil }
    var done: Double { counts ? Double(credits.passed) : credits.earned }
    var taking: Double { counts ? Double(credits.taking) : credits.inProgress }
    var goal: Double? { category.minCount.map(Double.init) ?? category.minCredits.flatMap { $0 > 0 ? $0 : nil } }
    var unit: String { counts ? "과목" : "학점" }
    var met: Bool {
        guard goal != nil else { return false }
        return (category.minCredits.map { credits.earned >= $0 } ?? true) && (category.minCount.map { credits.passed >= $0 } ?? true)
    }
    var over: Bool { category.maxCredits.map { $0 > 0 && credits.earned > $0 } ?? false }

    var body: some View {
        let idle = goal == nil && done + taking == 0
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title ?? category.name)
                        .font(header ? Theme.Typeface.figureSmall : Theme.Typeface.body)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                        .lineLimit(1)
                    if let note { Text(note).font(Theme.Typeface.caption).foregroundStyle(over ? Theme.Palette.warning : Theme.Palette.textTertiary) }
                }
                Spacer(minLength: Theme.Space.s)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(done.formatted()).font(header ? Theme.Typeface.figureSmall : Theme.Typeface.bodyStrong)
                        .foregroundStyle(idle ? Theme.Palette.textTertiary : Theme.Palette.text)
                    if let goal { Text("/ \(goal.formatted())").foregroundStyle(Theme.Palette.textTertiary) }
                    Text(unit).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
                .monospacedDigit()
                ProgressRing(done: done, taking: taking, goal: goal, met: met, over: over)
            }
            if header, goal != nil {
                CreditBar(credits: CategoryCredits(earned: done, inProgress: taking), goal: goal, met: met, height: 6)
            }
        }
    }

    /// `수강 중 4 · 4학점 남음`, `최대 18 초과`: what the figure alone doesn't say.
    var note: String? {
        var parts: [String] = []
        if taking > 0 { parts.append("수강 중 \(taking.formatted())") }
        if over, let cap = category.maxCredits {
            parts.append("최대 \(cap.formatted())학점 초과")
        } else if let goal, !met {
            parts.append("\((goal - done).formatted())\(unit) 남음")
        } else if let cap = category.maxCredits, cap > 0, cap != category.minCredits {
            parts.append("최대 \(cap.formatted())학점")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Progress toward a goal in the space of an icon: earned solid, in-progress faint, a check once met.
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
                    Circle().trim(from: 0, to: min(1, (done + taking) / goal)).stroke(Theme.Palette.textTertiary.opacity(0.45), lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, done / goal)).stroke(Theme.Palette.textSecondary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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

/// Earned credits solid, in-progress ones faint, scaled to the requirement (or to the credits when there is none).
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
                Capsule().fill(color.opacity(Theme.Opacity.projected)).frame(width: w * min(1, (credits.earned + credits.inProgress) / scale))
                Capsule().fill(color).frame(width: w * min(1, credits.earned / scale))
            }
        }
        .frame(height: height)
    }
}

/// One category, new or existing, saved to catalog.json.
struct RequirementSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RequirementCategory
    @State private var removing = false
    let isNew: Bool

    init(category: RequirementCategory) {
        _draft = State(initialValue: category)
        isNew = category.name.isEmpty
    }

    var body: some View {
        let others = workspace.requirementCatalog.categories.filter { $0.id != draft.id }.sorted { $0.name < $1.name }
        SheetForm(title: isNew ? "분류 추가" : "\(draft.name) 요건", confirm: "저장", disabled: draft.name.isEmpty, carded: false, width: 560,
                  deleteTitle: isNew ? nil : "분류 삭제", onDelete: { removing = true }) {
            Block("분류") {
                Card {
                    FormRow(label: "이름") { InlineField("예: 전공선택", text: $draft.name) }
                    FormRow(label: "묶음", detail: "졸업 요건 표의 큰 갈래") { InlineField("예: 기초‧교양", text: $draft.group) }
                    FormRow(label: "상위 분류") {
                        SearchSelect(selection: $draft.parentId, options: [PickOption(id: UUID?.none, title: "없음")]
                            + RequirementsView.tree(others).map { PickOption(id: Optional($0.category.id), title: $0.category.name, detail: $0.category.group, depth: $0.depth) })
                    }
                    FormRow(label: "과정", detail: "그 과정을 선언했을 때만 보입니다") {
                        let programs = workspace.transcript.graduation.programs.map(\.codeId) + [draft.programId].compactMap { $0 }
                        ChoiceMenu(selection: $draft.programId, options: [(UUID?.none, "공통")] + programs.uniqued().map { id in
                            (Optional(id), workspace.catalog.codes.first { $0.id == id }.map { "\($0.prefix) \($0.department)" } ?? "알 수 없는 코드")
                        })
                    }
                    FormRow(label: "전공", detail: "전공 GPA에 넣습니다", last: true) { Switch(isOn: $draft.isMajor) }
                }
            }
            Block("기준", note: "비워 두면 없는 것으로 봅니다") {
                Card {
                    FormRow(label: "최소 학점") { TextField("없음", value: $draft.minCredits, format: .number).pill(width: 72) }
                    FormRow(label: "최대 인정 학점", detail: "최상위 분류의 초과분은 졸업 학점에서 뺍니다") {
                        TextField("없음", value: $draft.maxCredits, format: .number).pill(width: 72)
                    }
                    FormRow(label: "최소 과목 수", detail: "콜로퀴움처럼 학점 없는 요건") { TextField("없음", value: $draft.minCount, format: .number).pill(width: 72) }
                    FormRow(label: "이중 계산 상한", detail: "다른 과정 분류와 함께 셀 수 있는 학점. 복수전공 9, 부전공 0", last: true) {
                        TextField("없음", value: $draft.maxSharedCredits, format: .number).pill(width: 72)
                    }
                }
            }
            FormTextArea(label: "인정 과목과 출처", text: Binding(get: { draft.rule ?? "" }, set: { draft.rule = $0.isEmpty ? nil : $0 }), height: 64)
        } onConfirm: {
            var catalog = workspace.catalog
            if let i = catalog.categories.firstIndex(where: { $0.id == draft.id }) { catalog.categories[i] = draft } else { catalog.categories.append(draft) }
            workspace.saveCatalog(catalog)
            dismiss()
        }
        .confirmationDialog(Self.removeTitle(draft), isPresented: $removing) {
            Button("삭제", role: .destructive) {
                Self.remove(draft, workspace: workspace)
                dismiss()
            }
        } message: {
            Self.removeMessage
        }
    }

    static func removeTitle(_ category: RequirementCategory) -> String { "‘\(category.name)’ 분류를 지울까요?" }

    static let removeMessage = Text("이 분류를 쓰던 과목은 분류 없는 과목이 됩니다.")

    /// Its children move up to the top level rather than going with it.
    static func remove(_ category: RequirementCategory, workspace: Workspace) {
        var catalog = workspace.catalog
        catalog.categories.removeAll { $0.id == category.id }
        for i in catalog.categories.indices where catalog.categories[i].parentId == category.id { catalog.categories[i].parentId = nil }
        workspace.saveCatalog(catalog)
    }
}

/// Categories a course counts toward; a course may sit in several (e.g. 전공선택 and a minor).
struct CategoryMenu: View {
    @Environment(Workspace.self) private var workspace
    @Binding var selection: [UUID]
    /// Given, a category that would count it toward two programs it may not share between (학사편람) can't be picked.
    var course: Course?

    var body: some View {
        let catalog = workspace.requirementCatalog
        // Only a pick that makes it worse is blocked, so a course already listed wrong can still be moved elsewhere.
        let already = course.map { GPACalculator.blocksSharing($0, categoryIds: selection, catalog: catalog) } ?? true
        SearchMultiSelect(selection: $selection, options: RequirementsView.tree(catalog.categories).map {
            let id = $0.category.id
            let blocked = !already && !selection.contains(id) && course.map { GPACalculator.blocksSharing($0, categoryIds: selection + [id], catalog: catalog) } == true
            return PickOption(id: id, title: $0.category.name, detail: blocked ? "강의 공유나 학과 인정 과목이 아니라 함께 셀 수 없습니다" : $0.category.rule,
                              section: $0.group, depth: $0.depth, disabled: blocked)
        }, placeholder: "분류 고르기")
    }
}

/// 내 정보, also a Settings tab. Set once and summarized in the page subtitle, so it opens from the header too.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("내 정보").font(Theme.Typeface.columnTitle)
            ProfileCard()
            Text("선언한 과정의 요건만 보입니다. 바꾸면 바로 저장됩니다.").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.m)
            HStack {
                Spacer()
                Button("닫기") { dismiss() }.buttonStyle(.pointing(.borderedProminent)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
        .controlSize(.large)
    }
}

/// School mail, admission year and declared programs, saved to transcript.json's `graduation`.
struct ProfileCard: View {
    @Environment(Workspace.self) private var workspace
    @State private var email = ""
    /// Until the draft is filled from the transcript, saving would clear the stored mail.
    @State private var loaded = false

    var body: some View {
        let rule = workspace.transcript.graduation
        let codes = workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
        let options = codes.map { PickOption(id: $0.id, title: "\($0.prefix) \($0.department)", detail: $0.program) }
        let save = { (change: (inout GraduationRule) -> Void) in
            var r = rule
            change(&r)
            if r != rule { workspace.saveGraduation(r) }
        }
        Card {
            FormRow(label: "학교 메일") {
                InlineField("name@gm.gist.ac.kr", text: $email)
            }
            FormRow(label: "입학 연도", detail: "학번마다 요건 표가 다릅니다") {
                TextField("예: 2025", value: Binding(get: { rule.admissionYear }, set: { y in save { $0.admissionYear = y } }), format: .number.grouping(.never))
                    .pill(width: 72)
            }
            // By position: the same program listed twice would otherwise collide, and the kind menu already names it.
            ForEach(Array(rule.programs.enumerated()), id: \.offset) { i, p in
                FormRow(label: "과정 \(i + 1)") {
                    SearchSelect(selection: Binding(get: { p.codeId }, set: { id in save { $0.programs[i].codeId = id } }), options: options)
                    ChoiceMenu(selection: Binding(get: { p.kind }, set: { k in save { $0.programs[i].kind = k } }),
                               options: StudentProgram.Kind.allCases.map { ($0, $0.label) })
                    Button("빼기", systemImage: "minus.circle") { save { $0.programs.remove(at: i) } }
                        .buttonStyle(.ghostIcon)
                }
                .contextMenu { Button("과정 빼기", role: .destructive) { save { $0.programs.remove(at: i) } } }
            }
            CardRow(last: true) {
                SearchPicker(options: options.filter { o in !rule.programs.contains { $0.codeId == o.id } },
                             pick: { id in save { $0.programs.append(.init(codeId: id, kind: $0.programs.contains { $0.kind == .major } ? .doubleMajor : .major)) } },
                             prompt: "학과 코드") {
                    Label("과정 추가", systemImage: "plus")
                }
                Spacer()
            }
        }
        .onAppear {
            email = rule.email
            loaded = true
        }
        // Typing pauses before saving, as in Settings: each save rewrites transcript.json.
        .task(id: email) {
            guard loaded else { return }
            try? await Task.sleep(for: .milliseconds(600))
            let e = email.trimmingCharacters(in: .whitespaces)
            guard !Task.isCancelled, e != workspace.transcript.graduation.email else { return }
            var r = workspace.transcript.graduation
            r.email = e
            workspace.saveGraduation(r)
        }
    }
}

extension StudentProgram.Kind {
    var label: String {
        switch self {
        case .major: "주전공"
        case .doubleMajor: "복수전공"
        case .minor: "부전공"
        case .intensive: "심화전공"
        }
    }
}
