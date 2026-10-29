import Algorithms
import FolioActions
import FolioDomain
import Foundation
import Observation

typealias RequirementCategory = FolioDomain.Category

@MainActor @Observable
final class RequirementsModel {
    let workspace: Workspace
    var editing: RequirementCategory?
    var removing: RequirementCategory?
    /// The category whose courses are showing in a popover.
    var showing: UUID?

    init(workspace: Workspace) { self.workspace = workspace }

    typealias GroupCard = (group: String, rows: [CategoryTreeRow])

    var catalog: Catalog { workspace.requirementCatalog }
    var courses: [Course] { workspace.allCourseRecords }
    var rule: GraduationRule { workspace.transcript.graduation }
    var audit: RequirementAudit { RequirementAudit(courses: courses, semesters: workspace.transcript.semesters, catalog: catalog) }
    var credits: [UUID: CategoryCredits] { GPACalculator.categoryCredits(courses: courses, catalog: catalog) }
    var listed: [UUID: [Course]] { GPACalculator.categoryCourses(courses: courses, catalog: catalog) }

    var subtitle: String {
        let parts = [rule.admissionYear.map { String(localized: .requirementsAdmissionYear(String($0))) }] + rule.programs.map { $0.title(in: workspace.catalog) }
        let line = parts.compactMap { $0 }.joined(separator: " · ")
        return line.isEmpty ? String(localized: .requirementsSubtitle) : line
    }

    func addCategory() { editing = RequirementCategory(device: workspace.device, at: .now, name: "") }

    // MARK: Notices

    func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    func suggestionsTitle(_ count: Int) -> String { String(localized: .requirementsSuggestionsTitle(count)) }

    func suggestionSource(_ s: HandbookClassifier.Suggestion) -> String { String(localized: .requirementsSuggestionSource(s.code, String(s.year))) }

    func suggestionChange(_ s: HandbookClassifier.Suggestion) -> String {
        names(course(s.courseId)?.categoryIds ?? []) + " → " + names(s.categoryIds)
    }

    func names(_ ids: [UUID]) -> String {
        let names = ids.compactMap { catalog.category($0)?.name }
        return names.isEmpty ? String(localized: .requirementsNone) : names.joined(separator: ", ")
    }

    func categoryName(_ id: UUID) -> String { catalog.category(id)?.name ?? "" }

    func overSharedTitle(_ s: SharedCredits) -> String {
        String(localized: .requirementsOverSharedTitle(categoryName(s.categoryId), (s.earned + s.inProgress).formatted(), s.cap.formatted()))
    }

    func overSharedDetail(_ s: SharedCredits) -> String { String(localized: .requirementsOverSharedDetail(categoryName(s.categoryId))) }

    func unallowedTitle(_ s: SharedCredits) -> String { String(localized: .requirementsUnallowedTitle(categoryName(s.categoryId), s.unallowed.count)) }

    func unallowedDetail(_ s: SharedCredits) -> String { String(localized: .requirementsUnallowedDetail(categoryName(s.categoryId))) }

    func unassignedTitle(_ count: Int) -> String { String(localized: .requirementsUnassignedTitle(count)) }

    /// `2026 봄학기 · 3학점 · 수강 중`; an unassigned course leaves out whether it is being taken.
    func courseDetail(_ course: Course, showsTaking: Bool = true) -> String {
        [workspace.semester(of: course)?.title, GradesModel.credits(course.credits),
         showsTaking && course.finalGrade == nil ? String(localized: .gradesEnrolled) : nil].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Figures

    var stats: [StatStrip.Item] {
        let progress = GPACalculator.graduation(semesters: workspace.transcript.semesters, courses: courses, catalog: catalog)
        let gpa = GPACalculator.cumulative(semesters: workspace.transcript.semesters, courses: courses, catalog: catalog).gpa
        let unassigned = audit.unassigned.count
        return [
            .init(title: String(localized: .requirementsGraduationCredits), value: "\(progress.counted.formatted()) / \(rule.totalCredits.formatted())",
                  detail: [progress.inProgress > 0 ? String(localized: .requirementsTaking(progress.inProgress.formatted())) : nil,
                           progress.earned > progress.counted ? String(localized: .requirementsOverCapExcluded((progress.earned - progress.counted).formatted())) : nil]
                      .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                  tone: progress.counted >= rule.totalCredits ? .success : .plain),
            .init(title: String(localized: .requirementsRemainingCredits), value: "\(max(0, rule.totalCredits - progress.counted - progress.inProgress).formatted())",
                  detail: String(localized: .requirementsRemainingCreditsDetail)),
            .init(title: String(localized: .requirementsGpa), value: GPACalculator.label(gpa), detail: String(localized: .requirementsMinGpa(String(format: "%.1f", rule.minGPA))),
                  tone: (gpa ?? 0) >= rule.minGPA ? .plain : .danger, sensitive: true),
            // A detail on every item keeps the figures on one line across the strip.
            .init(title: String(localized: .requirementsUnassigned), value: "\(unassigned)",
                  detail: String(localized: unassigned == 0 ? .requirementsUnassignedNone : .requirementsUnassignedHint),
                  tone: unassigned == 0 ? .plain : .warning),
        ]
    }

    var cards: [GroupCard] {
        let tree = Category.tree(catalog.categories)
        return Category.groups(catalog.categories).map { group in (group, tree.filter { $0.group == group }) }
    }

    /// Largest first so the long 기초‧교양 card anchors a column and the small ones fill the other.
    var columns: [[GroupCard]] { Self.balance(cards.sorted { $0.rows.count > $1.rows.count }, by: \.rows.count) }

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

    /// A group's total is its lone top-level category (전공 → 전공학점) or the one named like it (기초‧교양), so every
    /// card that has one leads with it and its bar.
    static func header(of card: GroupCard) -> CategoryTreeRow? {
        let roots = card.rows.filter { $0.depth == 0 }
        return roots.count == 1 ? roots[0] : roots.first { $0.category.name == card.group }
    }

    static func groupTitle(_ group: String) -> String { group.isEmpty ? String(localized: .requirementsGroupOther) : group }

    /// Shown whenever a handbook is loaded, so the feature stays visible after every course is classified.
    var showsHandbookNote: Bool { !catalog.handbooks.isEmpty && audit.suggestions.isEmpty }

    var handbookNote: String {
        String(localized: .requirementsHandbookNote(catalog.handbooks.map { "\($0.year)" }.joined(separator: ", ")))
    }

    func sortedForList(_ courses: [Course]) -> [Course] {
        let order = Dictionary(keepingFirst: workspace.transcript.semesters.map { ($0.id, $0.order) })
        return courses.sorted { (order[$0.semesterId ?? UUID()] ?? .max, $0.title) < (order[$1.semesterId ?? UUID()] ?? .max, $1.title) }
    }

    func listDetail(_ course: Course) -> String {
        [workspace.semester(of: course)?.shortTitle, GradesModel.credits(course.credits)].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Actions

    func setCategories(_ courseId: UUID, _ ids: [UUID]) { workspace.run(CourseSet(course: courseId, [.categories(ids)])) }

    func applyAll(_ suggestions: [HandbookClassifier.Suggestion]) { for s in suggestions { setCategories(s.courseId, s.categoryIds) } }

    func approveSharing(_ courseId: UUID) { workspace.run(CourseSet(course: courseId, [.sharingApproved(true)])) }

    static func removeTitle(_ category: RequirementCategory) -> String { String(localized: .requirementsRemoveConfirm(category.name)) }

    /// Its children move up to the top level rather than going with it.
    static func remove(_ category: RequirementCategory, in workspace: Workspace) {
        var catalog = workspace.catalog
        catalog.categories.removeAll { $0.id == category.id }
        for i in catalog.categories.indices where catalog.categories[i].parentId == category.id { catalog.categories[i].parentId = nil }
        workspace.saveCatalog(catalog)
    }

    /// Only a pick that makes it worse is blocked, so a course already listed wrong can still be moved elsewhere.
    static func categoryOptions(_ catalog: Catalog, selection: [UUID], course: Course?) -> [PickOption<UUID>] {
        let already = course.map { GPACalculator.blocksSharing($0, categoryIds: selection, catalog: catalog) } ?? true
        return Category.tree(catalog.categories).map {
            let id = $0.category.id
            let blocked = !already && !selection.contains(id) && course.map { GPACalculator.blocksSharing($0, categoryIds: selection + [id], catalog: catalog) } == true
            return PickOption(id: id, title: $0.category.name, detail: blocked ? String(localized: .requirementsCategoryBlocked) : $0.category.rule,
                              section: $0.group, depth: $0.depth, disabled: blocked)
        }
    }
}

/// The requirement sheet's draft, saved into catalog.json only on confirm.
@MainActor @Observable
final class RequirementEditModel {
    let workspace: Workspace
    var draft: RequirementCategory
    let isNew: Bool

    init(workspace: Workspace, category: RequirementCategory) {
        self.workspace = workspace
        draft = category
        isNew = category.name.isEmpty
    }

    var title: String { isNew ? String(localized: .requirementsAddCategory) : String(localized: .requirementsSheetTitle(draft.name)) }

    var parentOptions: [PickOption<UUID?>] {
        let others = workspace.requirementCatalog.categories.filter { $0.id != draft.id }.sorted { $0.name < $1.name }
        return [PickOption(id: UUID?.none, title: String(localized: .requirementsNone))]
            + Category.tree(others).map { PickOption(id: Optional($0.category.id), title: $0.category.name, detail: $0.category.group, depth: $0.depth) }
    }

    var programOptions: [(UUID?, String)] {
        let programs = workspace.transcript.graduation.programs.map(\.codeId) + [draft.programId].compactMap { $0 }
        return [(UUID?.none, String(localized: .requirementsProgramCommon))] + programs.uniqued().map { id in
            (Optional(id), workspace.catalog.codes.first { $0.id == id }.map { "\($0.prefix) \($0.department)" } ?? String(localized: .requirementsUnknownCode))
        }
    }

    func confirm() {
        var catalog = workspace.catalog
        if let i = catalog.categories.firstIndex(where: { $0.id == draft.id }) { catalog.categories[i] = draft } else { catalog.categories.append(draft) }
        workspace.saveCatalog(catalog)
    }

    func remove() { RequirementsModel.remove(draft, in: workspace) }
}

/// 내 정보: transcript.json's graduation profile, saved as it changes.
@MainActor @Observable
final class ProfileModel {
    let workspace: Workspace
    var email = ""
    /// Until the draft is filled from the transcript, saving would clear the stored mail.
    private var loaded = false

    init(workspace: Workspace) { self.workspace = workspace }

    var rule: GraduationRule { workspace.transcript.graduation }

    var codeOptions: [PickOption<UUID>] {
        workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
            .map { PickOption(id: $0.id, title: "\($0.prefix) \($0.department)", detail: $0.program) }
    }

    var addableOptions: [PickOption<UUID>] { codeOptions.filter { o in !rule.programs.contains { $0.codeId == o.id } } }

    func update(_ change: (inout GraduationRule) -> Void) {
        var r = rule
        change(&r)
        if r != rule { workspace.run(GraduationSet(rule: r)) }
    }

    /// The first program declared is the major; any after it starts as a double major.
    func addProgram(_ codeId: UUID) {
        update { $0.programs.append(.init(codeId: codeId, kind: $0.programs.contains { $0.kind == .major } ? .doubleMajor : .major)) }
    }

    func load() {
        email = rule.email
        loaded = true
    }

    func saveEmail() {
        guard loaded else { return }
        let e = email.trimmingCharacters(in: .whitespaces)
        guard e != rule.email else { return }
        update { $0.email = e }
    }
}

extension StudentProgram {
    /// `EC 주전공`, `AI 복수전공`.
    func title(in catalog: Catalog) -> String {
        (catalog.codes.first { $0.id == codeId }?.prefix ?? "?") + " " + kind.label
    }
}

extension StudentProgram.Kind {
    var label: String {
        switch self {
        case .major: String(localized: .programKindMajor)
        case .doubleMajor: String(localized: .programKindDoubleMajor)
        case .minor: String(localized: .programKindMinor)
        case .intensive: String(localized: .programKindIntensive)
        }
    }
}
