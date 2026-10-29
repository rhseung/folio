import Foundation

/// docs/SPEC.md "학점과 GPA 계산". Totals are always computed from courses, never stored.
public enum GPACalculator {
    /// `3.800`, or `-` with nothing graded yet.
    public static func label(_ gpa: Double?) -> String { gpa.map { String(format: "%.3f", $0) } ?? "-" }

    public struct Summary: Sendable, Equatable {
        /// Credits of courses whose grade counts toward credits (S counts; U, W don't).
        public var totalCredits: Double
        /// Credits that enter the GPA.
        public var effectiveCredits: Double
        public var gradePoints: Double

        public init(totalCredits: Double, effectiveCredits: Double, gradePoints: Double) {
            self.totalCredits = totalCredits
            self.effectiveCredits = effectiveCredits
            self.gradePoints = gradePoints
        }

        public var gpa: Double? {
            effectiveCredits > 0 ? gradePoints / effectiveCredits : nil
        }

        public static let zero = Summary(totalCredits: 0, effectiveCredits: 0, gradePoints: 0)

        static func + (a: Self, b: Self) -> Self {
            Summary(totalCredits: a.totalCredits + b.totalCredits, effectiveCredits: a.effectiveCredits + b.effectiveCredits, gradePoints: a.gradePoints + b.gradePoints)
        }
    }

    /// Courses without a final grade (in progress) count nowhere.
    public static func summary(of courses: [Course], catalog: Catalog) -> Summary {
        courses.reduce(.zero) { sum, course in
            guard let grade = catalog.grade(course.finalGrade) else { return sum }
            var s = Summary.zero
            if grade.countsInCredits { s.totalCredits = course.credits }
            if grade.countsInGpa, course.credits > 0, let points = grade.points {
                s.effectiveCredits = course.credits
                s.gradePoints = points * course.credits
            }
            return sum + s
        }
    }

    /// One semester. A credited term (인정학기) contributes only its credited hours, never GPA.
    public static func semester(_ semester: Semester, courses: [Course], catalog: Catalog) -> Summary {
        guard semester.term != .credited else {
            return Summary(totalCredits: semester.creditedHours ?? 0, effectiveCredits: 0, gradePoints: 0)
        }
        return summary(of: courses.filter { $0.semesterId == semester.id }, catalog: catalog)
    }

    /// Credited terms (인정학기) add their hours to total credits only.
    public static func cumulative(semesters: [Semester], courses: [Course], catalog: Catalog) -> Summary {
        var result = summary(of: courses.filter { c in semesters.contains { $0.id == c.semesterId && $0.term != .credited } }, catalog: catalog)
        result.totalCredits += semesters.filter { $0.term == .credited }.compactMap(\.creditedHours).reduce(0, +)
        return result
    }

    public static func countsTowardMajor(_ course: Course, catalog: Catalog) -> Bool {
        course.countsTowardMajor ?? course.categoryIds.contains { catalog.category($0)?.isMajor == true }
    }

    public static func major(courses: [Course], catalog: Catalog) -> Summary {
        summary(of: courses.filter { countsTowardMajor($0, catalog: catalog) }, catalog: catalog)
    }

    /// GPA of one declared program (EC 주전공, AI 복수전공): courses in a category that belongs to it. A course marked as
    /// not counting toward a major stays out.
    public static func program(_ codeId: UUID, courses: [Course], catalog: Catalog) -> Summary {
        summary(of: courses.filter { course in
            course.countsTowardMajor != false && course.categoryIds.contains { catalog.category($0).flatMap(catalog.program(of:)) == codeId }
        }, catalog: catalog)
    }

    /// Credits a program still needs: the minimums of its top-level categories less the credits graded so far.
    /// In-progress courses are still to be graded, so they count as remaining.
    public static func programRemaining(_ codeId: UUID, courses: [Course], catalog: Catalog) -> Double {
        let credits = categoryCredits(courses: courses, catalog: catalog)
        return catalog.categories
            .filter { c in catalog.program(of: c) == codeId && c.parentId.flatMap(catalog.category).flatMap(catalog.program(of:)) != codeId }
            .reduce(0) { $0 + max(0, ($1.minCredits ?? 0) - (credits[$1.id]?.earned ?? 0)) }
    }

    /// Average grade points needed over `remainingCredits` to reach `target` cumulative GPA. Nil if no credits remain.
    public static func requiredAverage(target: Double, current: Summary, remainingCredits: Double) -> Double? {
        guard remainingCredits > 0 else { return nil }
        return (target * (current.effectiveCredits + remainingCredits) - current.gradePoints) / remainingCredits
    }
}
