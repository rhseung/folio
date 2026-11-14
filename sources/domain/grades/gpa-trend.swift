import Foundation

extension GPACalculator {
    public static func trend(semesters: [Semester], courses: [Course], catalog: Catalog) -> [GPATrendPoint] {
        semesters.indices.compactMap { i in
            let s = semesters[i]
            guard s.term != .credited else { return nil }
            let summary = semester(s, courses: courses, catalog: catalog)
            guard let gpa = summary.gpa else { return nil }
            return GPATrendPoint(
                semester: s, gpa: gpa, credits: summary.effectiveCredits,
                cumulative: cumulative(semesters: Array(semesters[...i]), courses: courses, catalog: catalog).gpa)
        }
    }
}
