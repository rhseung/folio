import Foundation

/// A requirement row transcribed from the handbook. `parent` is a category name.
public struct RequirementSpec: Codable, Sendable, Equatable {
    public var name: String
    public var group: String
    public var isMajor: Bool
    public var parent: String?
    public var minCredits: Double?
    public var maxCredits: Double?
    public var minCount: Int?
    public var maxSharedCredits: Double?
    public var rule: String?
    /// Renames a category instead of adding one, so courses already in it stay put.
    public var renamedFrom: String?
    /// Course code prefix of the program this belongs to (`EC`); nil for common requirements.
    public var program: String?
}

/// A requirements file: the student's track plus the categories. A bare array of specs is read as categories only.
public struct RequirementFile: Codable, Sendable {
    public struct Program: Codable, Sendable {
        public var code: String
        public var kind: StudentProgram.Kind
    }

    public var admissionYear: Int?
    public var programs: [Program]?
    public var categories: [RequirementSpec]

    public init(from decoder: any Decoder) throws {
        if let rows = try? [RequirementSpec](from: decoder) {
            categories = rows
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        admissionYear = try c.decodeIfPresent(Int.self, forKey: .admissionYear)
        programs = try c.decodeIfPresent([Program].self, forKey: .programs)
        categories = try c.decodeIfPresent([RequirementSpec].self, forKey: .categories) ?? []
    }
}

public enum RequirementImporter {
    public struct Result: Sendable {
        public var categories: [Category]
        public var added: [String]
        public var changed: [String]
        /// Existing categories the file doesn't mention. They are kept: courses may still point at them.
        public var untouched: [String]
    }

    /// Matches by name (or `renamedFrom`), keeping each category's ID so course assignments survive.
    /// The undergraduate code for a prefix; the code table also lists the graduate one under the same prefix.
    public static func code(_ prefix: String, in codes: [CourseCode]) -> CourseCode? {
        codes.first { $0.prefix == prefix && $0.program == "학사과정" } ?? codes.first { $0.prefix == prefix }
    }

    public static func merge(_ rows: [RequirementSpec], into existing: [Category], codes: [CourseCode] = [], device: DeviceID, now: Date) -> Result {
        var categories = existing
        var added: [String] = [], changed: [String] = []
        var seen = Set<UUID>()
        for row in rows {
            let i = categories.firstIndex { $0.name == row.name } ?? row.renamedFrom.flatMap { old in categories.firstIndex { $0.name == old } }
            var c = i.map { categories[$0] } ?? Category(device: device, at: now, name: row.name)
            let before = c
            c.name = row.name
            c.group = row.group
            c.isMajor = row.isMajor
            c.minCredits = row.minCredits
            c.maxCredits = row.maxCredits
            c.minCount = row.minCount
            c.maxSharedCredits = row.maxSharedCredits
            c.rule = row.rule
            c.programId = row.program.flatMap { code($0, in: codes)?.id }
            if let i {
                if c != before { c.touch(by: device, at: now); categories[i] = c; changed.append(row.name) }
            } else {
                categories.append(c)
                added.append(row.name)
            }
            seen.insert(c.id)
        }
        // Parents last: a row may name a parent that appears after it.
        for row in rows {
            guard let i = categories.firstIndex(where: { $0.name == row.name }) else { continue }
            let parent = row.parent.flatMap { name in categories.first { $0.name == name }?.id }
            guard categories[i].parentId != parent else { continue }
            categories[i].parentId = parent
            categories[i].touch(by: device, at: now)
            if !added.contains(row.name), !changed.contains(row.name) { changed.append(row.name) }
        }
        let untouched = categories.filter { !seen.contains($0.id) }.map(\.name)
        return Result(categories: categories, added: added, changed: changed, untouched: untouched)
    }
}
