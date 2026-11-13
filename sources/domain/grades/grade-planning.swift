import Foundation

public struct CategoryCredits: Sendable, Equatable {
    public var earned: Double = 0
    public var inProgress: Double = 0
    public var passed = 0
    public var taking = 0

    public init(earned: Double = 0, inProgress: Double = 0, passed: Int = 0, taking: Int = 0) {
        self.earned = earned
        self.inProgress = inProgress
        self.passed = passed
        self.taking = taking
    }
}

public struct SharedCredits: Sendable, Equatable {
    public var categoryId: UUID
    public var cap: Double
    public var courses: [Course]
    public var earned: Double
    public var inProgress: Double
    public var unallowed: [Course] = []
    public var excessEarned: Double { Swift.max(0, earned - cap) + unallowed.filter { $0.finalGrade != nil }.map(\.credits).reduce(0, +) }
    public var excessInProgress: Double {
        Swift.max(0, earned + inProgress - cap) - Swift.max(0, earned - cap)
            + unallowed.filter { $0.finalGrade == nil }.map(\.credits).reduce(0, +)
    }
    public var isOver: Bool { earned + inProgress > cap }
}

public struct GraduationProgress: Sendable, Equatable {
    public var earned: Double
    public var counted: Double
    public var inProgress: Double
}

extension GPACalculator {
    public static func simulate(_ expected: [UUID: UUID?], courses: [Course]) -> [Course] {
        courses.map { course in
            var course = course
            if let grade = expected[course.id] { course.finalGrade = grade }
            return course
        }
    }

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

    public static func categoryCourses(courses: [Course], catalog: Catalog) -> [UUID: [Course]] {
        var result: [UUID: [Course]] = [:]
        for course in courses {
            for id in countedCategories(of: course, catalog: catalog) ?? [] { result[id, default: []].append(course) }
        }
        return result
    }

    static func countedCategories(of course: Course, catalog: Catalog) -> Set<UUID>? {
        let earned = catalog.grade(course.finalGrade)?.earnsCredits == true
        guard earned || course.finalGrade == nil else { return nil }
        return course.categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
    }

    static func ancestry(_ id: UUID, catalog: Catalog) -> Set<UUID> {
        var ids = Set<UUID>()
        var next: UUID? = id
        // `inserted`는 손으로 고친 catalog의 부모 순환도 막는다.
        while let current = next, ids.insert(current).inserted { next = catalog.category(current)?.parentId }
        return ids
    }

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

    public static func canShare(_ course: Course, under capped: Category, catalog: Catalog) -> Bool {
        let others = otherPrograms(of: course, than: capped, catalog: catalog)
        if others.isEmpty || course.sharingApproved == true { return true }
        // catalog는 같은 접두어를 학사편람 연도마다 다른 id로 둘 수 있으므로, 접두어로 비교한다.
        let prefixes = Set(course.codes.compactMap { catalog.code($0)?.prefix })
        return (others + [catalog.program(of: capped)].compactMap { $0 }).allSatisfy {
            catalog.code($0).map { prefixes.contains($0.prefix) } ?? false
        }
    }

    public static func blocksSharing(_ course: Course, categoryIds: [UUID], catalog: Catalog) -> Bool {
        var course = course
        course.categoryIds = categoryIds
        let ids = categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
        return ids.contains { id in
            guard let c = catalog.category(id), c.maxSharedCredits != nil else { return false }
            return !canShare(course, under: c, catalog: catalog)
        }
    }

    static func otherPrograms(of course: Course, than capped: Category, catalog: Catalog) -> [UUID] {
        let own = catalog.program(of: capped)
        let ids = course.categoryIds.reduce(into: Set<UUID>()) { $0.formUnion(ancestry($1, catalog: catalog)) }
        return Array(Set(ids.compactMap { catalog.category($0).flatMap(catalog.program(of:)) }.filter { $0 != own }))
    }

    // 상한이 있는 하위 분류는 상위 분류 안에 있으므로, 둘 다 빼면 두 번 센다. 그래서 최상위 상한만 적용한다.
    public static func graduation(semesters: [Semester], courses: [Course], catalog: Catalog) -> GraduationProgress {
        let regular = Set(semesters.filter { $0.term != .credited }.map(\.id))
        let earned =
            semesters.compactMap(\.creditedHours).reduce(0, +)
            + courses
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
