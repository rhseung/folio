import Foundation

/// docs/SPEC.md "성적 화면": the semester what-if and graduation requirements.
public struct CategoryCredits: Sendable, Equatable {
    /// Graded courses whose grade counts toward credits.
    public var earned: Double = 0
    /// Courses without a final grade yet.
    public var inProgress: Double = 0
    /// Course counts, for requirements measured in courses (zero-credit colloquia, arts/PE).
    public var passed = 0
    public var taking = 0

    public init(earned: Double = 0, inProgress: Double = 0, passed: Int = 0, taking: Int = 0) {
        self.earned = earned
        self.inProgress = inProgress
        self.passed = passed
        self.taking = taking
    }
}

/// Credits a capped category shares with another program's categories, and the courses behind them.
public struct SharedCredits: Sendable, Equatable {
    public var categoryId: UUID
    public var cap: Double
    /// Courses allowed to share; `earned` and `inProgress` are theirs.
    public var courses: [Course]
    public var earned: Double
    public var inProgress: Double
    /// Listed under both but neither a shared-code nor an approved course, so not counted here at all.
    public var unallowed: [Course] = []
    /// Past the cap, graded credits go first: in-progress ones only lose what the graded ones left of it.
    public var excessEarned: Double { Swift.max(0, earned - cap) + unallowed.filter { $0.finalGrade != nil }.map(\.credits).reduce(0, +) }
    public var excessInProgress: Double {
        Swift.max(0, earned + inProgress - cap) - Swift.max(0, earned - cap) + unallowed.filter { $0.finalGrade == nil }.map(\.credits).reduce(0, +)
    }
    public var isOver: Bool { earned + inProgress > cap }
}

public struct GraduationProgress: Sendable, Equatable {
    /// Earned credits, credited terms included.
    public var earned: Double
    /// `earned` less what top-level categories hold above their maximum, e.g. major credits past 42.
    public var counted: Double
    public var inProgress: Double
}

extension GPACalculator {
    /// `courses` with the grades in `expected` in place of the recorded ones (a nil value means ungraded),
    /// to feed `semester` and `cumulative` for a what-if.
    public static func simulate(_ expected: [UUID: UUID?], courses: [Course]) -> [Course] {
        courses.map { course in
            var course = course
            if let grade = expected[course.id] { course.finalGrade = grade }
            return course
        }
    }

    /// Credits per category. A course also counts toward every ancestor of its categories, once each,
    /// so a child requirement and its parent's total both see it. Shared credits past a category's
    /// `maxSharedCredits` come off it and its ancestors; course counts stay, as the courses were still taken.
    public static func categoryCredits(courses: [Course], catalog: Catalog) -> [UUID: CategoryCredits] {
        var result: [UUID: CategoryCredits] = [:]
        for course in courses {
            guard let ids = countedCategories(of: course, catalog: catalog) else { continue }
            let earned = course.finalGrade != nil
            for id in ids {
                if earned {
                    result[id, default: .init()].earned += course.credits
                    result[id, default: .init()].passed += 1
                } else {
                    result[id, default: .init()].inProgress += course.credits
                    result[id, default: .init()].taking += 1
                }
            }
        }
        for s in shared(courses: courses, catalog: catalog) {
            for id in ancestry(s.categoryId, catalog: catalog) {
                result[id]?.earned -= s.excessEarned
                result[id]?.inProgress -= s.excessInProgress
            }
        }
        return result
    }

    /// The courses behind each category's credits, by the same rule: passed or still in progress, under the
    /// category or any of its descendants.
    public static func categoryCourses(courses: [Course], catalog: Catalog) -> [UUID: [Course]] {
        var result: [UUID: [Course]] = [:]
        for course in courses {
            for id in countedCategories(of: course, catalog: catalog) ?? [] { result[id, default: []].append(course) }
        }
        return result
    }

    /// A course's categories and all their ancestors, or nil when it counts toward none: failed, U or W.
    static func countedCategories(of course: Course, catalog: Catalog) -> Set<UUID>? {
        let earned = catalog.grade(course.finalGrade)?.earnsCredits == true
        guard earned || course.finalGrade == nil else { return nil }
        return course.categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
    }

    /// The category and its ancestors.
    static func ancestry(_ id: UUID, catalog: Catalog) -> Set<UUID> {
        var ids = Set<UUID>()
        var next: UUID? = id
        // `inserted` also stops a parent cycle in a hand-edited catalog.
        while let current = next, ids.insert(current).inserted { next = catalog.category(current)?.parentId }
        return ids
    }

    /// For each category with `maxSharedCredits`, the courses also counted toward a category of another program.
    /// Common categories (no program) are not another program, so 기초‧교양 never uses up the double major's 9.
    public static func shared(courses: [Course], catalog: Catalog) -> [SharedCredits] {
        catalog.categories.compactMap { c in
            guard let cap = c.maxSharedCredits else { return nil }
            var s = SharedCredits(categoryId: c.id, cap: cap, courses: [], earned: 0, inProgress: 0)
            for course in courses {
                guard let ids = countedCategories(of: course, catalog: catalog), ids.contains(c.id),
                      !otherPrograms(of: course, than: c, catalog: catalog).isEmpty
                else { continue }
                if !canShare(course, under: c, catalog: catalog) { s.unallowed.append(course); continue }
                s.courses.append(course)
                if course.finalGrade != nil { s.earned += course.credits } else { s.inProgress += course.credits }
            }
            return s.courses.isEmpty && s.unallowed.isEmpty ? nil : s
        }
    }

    /// 학사편람: a course counts toward a capped category and another program's only when it is shared between them
    /// (it carries every one of their codes) or the department approved it. True when there is nothing to share.
    public static func canShare(_ course: Course, under capped: Category, catalog: Catalog) -> Bool {
        let others = otherPrograms(of: course, than: capped, catalog: catalog)
        if others.isEmpty || course.sharingApproved == true { return true }
        // By prefix: the catalog can hold the same prefix twice (one per handbook year), under different ids.
        let prefixes = Set(course.codes.compactMap { catalog.code($0)?.prefix })
        return (others + [catalog.program(of: capped)].compactMap { $0 }).allSatisfy { catalog.code($0).map { prefixes.contains($0.prefix) } ?? false }
    }

    /// Whether listing the course under `categoryIds` would share it where it may not; for blocking a pick before it is made.
    public static func blocksSharing(_ course: Course, categoryIds: [UUID], catalog: Catalog) -> Bool {
        var course = course
        course.categoryIds = categoryIds
        let ids = categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
        return ids.contains { id in
            guard let c = catalog.category(id), c.maxSharedCredits != nil else { return false }
            return !canShare(course, under: c, catalog: catalog)
        }
    }

    /// The programs, other than the capped category's own, of the categories the course is listed under.
    static func otherPrograms(of course: Course, than capped: Category, catalog: Catalog) -> [UUID] {
        let own = catalog.program(of: capped)
        let ids = course.categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
        return Array(Set(ids.compactMap { catalog.category($0).flatMap(catalog.program(of:)) }.filter { $0 != own }))
    }

    /// Only top-level caps are applied: a capped child sits inside its parent, so subtracting both would count twice.
    public static func graduation(semesters: [Semester], courses: [Course], catalog: Catalog) -> GraduationProgress {
        let regular = Set(semesters.filter { $0.term != .credited }.map(\.id))
        let earned = semesters.compactMap(\.creditedHours).reduce(0, +) + courses
            .filter { regular.contains($0.semesterId ?? UUID()) && catalog.grade($0.finalGrade)?.earnsCredits == true }
            .map(\.credits).reduce(0, +)
        let credits = categoryCredits(courses: courses, catalog: catalog)
        let excess = catalog.categories.filter { $0.parentId == nil }.reduce(0.0) { sum, c in
            guard let max = c.maxCredits else { return sum }
            return sum + Swift.max(0, (credits[c.id]?.earned ?? 0) - max)
        }
        let inProgress = courses.filter { $0.finalGrade == nil }.map(\.credits).reduce(0, +)
        return GraduationProgress(earned: earned, counted: earned - excess, inProgress: inProgress)
    }
}
