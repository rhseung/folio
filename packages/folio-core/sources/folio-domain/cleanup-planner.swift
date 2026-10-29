import Foundation

/// A one-time plan that moves an unorganized GIST folder into the standard layout (docs/SPEC.md "기존 폴더 정리").
/// Only moves and renames; file contents are never touched.
public struct CleanupPlan: Codable, Sendable, Equatable {
    public var moves: [PlannedMove]
    /// GIST-relative paths left alone: non-academic folders and anything the user excluded.
    public var skipped: [String]

    public init(moves: [PlannedMove], skipped: [String]) {
        self.moves = moves
        self.skipped = skipped
    }
}

/// `from` and `to` are relative to the GIST root. `review` is nil when the rule was certain.
public struct PlannedMove: Codable, Sendable, Hashable {
    public var from: String
    public var to: String
    public var review: ReviewReason?

    public init(from: String, to: String, review: ReviewReason? = nil) {
        self.from = from
        self.to = to
        self.review = review
    }
}

public enum ReviewReason: String, Codable, Sendable, CaseIterable {
    case guessedWeek            // week taken from a lecture/chapter/leading number, not an explicit week
    case unknownWeek            // no number at all; numbered after the known ones
    case guessedNumber          // assignment number taken from a leading number
    case unknownNumber          // no assignment number; placed in `<prefix>00`
    case guessedExam            // which exam this belongs to is a guess (defaults to Midterm)
    case pastExamNameKept       // couldn't rename to `<year> <kind> (<source>)` without losing information
    case guessedFolder          // folder chosen from keywords in the name (e.g. textbook)
    case unknownFile            // no rule matched; parked in Archive
    case unknownFolder          // folder with no standard counterpart
    case nameCollision          // target existed; ` (n)` added
}

public enum CleanupPlanner {
    /// The spec's legacy-name table. Standard names (`Lectures`, `Assignments`, ...) are handled by CourseFolder.
    enum LegacyFolder {
        case lectures, assignments(AssignmentKind), labManuals, labReports, pastExams(source: String?), examReview, textbooks, notes
    }

    static let adminFolderNames: Set<String> = ["학사"]

    static func legacyFolder(_ name: String, siblings: Set<String>) -> LegacyFolder? {
        switch name {
        case "강의자료": return .lectures
        case "숙제", "Homeworks": return .assignments(.homework)
        case "Slow Problems": return .assignments(.slowProblem)
        case "Reports": return siblings.contains("Manuals") ? .labReports : .assignments(.report)
        case "Manuals": return .labManuals
        case "Exam Review": return .examReview
        case "Books": return .textbooks
        case "노트": return .notes
        default:
            guard name.hasPrefix("족보") else { return nil }
            let source = name.firstMatch(of: /\((.+)\)/).map { String($0.1) }
            return .pastExams(source: source)
        }
    }

    /// `labs` maps a GIST-relative course path to its experiment titles and their numbers, so reports named after an
    /// experiment land in that experiment's `Lab<NN>`; `labWeeks` gives each experiment's first week, so its manual
    /// becomes that week's lecture material.
    public static func plan(_ gist: FolderTree, skip: Set<String> = [], labs: [String: [String: Int]] = [:],
                            labWeeks: [String: [Int: Int]] = [:]) -> CleanupPlan {
        var moves: [PlannedMove] = []
        var skipped: [String] = []

        func isSkipped(_ path: String) -> Bool {
            skip.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        for semester in gist.children where semester.name != StandardLayout.metadataFolder {
            guard SemesterFolder(name: semester.name) != nil, !semester.isFile, !isSkipped(semester.name) else {
                skipped.append(semester.name)
                continue
            }
            let admin = "\(semester.name)/\(StandardLayout.adminFolder)"
            for child in semester.children {
                let path = "\(semester.name)/\(child.name)"
                if isSkipped(path) {
                    skipped.append(path)
                } else if child.isFile {
                    moves.append(.init(from: path, to: "\(admin)/\(child.name)"))
                } else if adminFolderNames.contains(child.name) {
                    moves += child.children.map { .init(from: "\(path)/\($0.name)", to: "\(admin)/\($0.name)") }
                } else if child.name == StandardLayout.adminFolder {
                    continue
                } else if StandardLayout.isCourseFolderName(child.name) {
                    var planner = CoursePlanner(course: child, labs: labs[path] ?? [:], labWeeks: labWeeks[path] ?? [:])
                    moves += planner.plan().map {
                        .init(from: "\(path)/\($0.from)", to: "\(path)/\($0.to)", review: $0.review)
                    }
                } else {
                    skipped.append(path)
                }
            }
        }
        return CleanupPlan(moves: moves.filter { $0.from != $0.to }, skipped: skipped)
    }
}

/// Plans one course folder. Paths are relative to the course folder.
struct CoursePlanner {
    let course: FolderTree
    let labs: [String: Int]
    let labWeeks: [Int: Int]
    var moves: [PlannedMove] = []
    var lectures: [(path: String, name: String)] = []

    init(course: FolderTree, labs: [String: Int] = [:], labWeeks: [Int: Int] = [:]) {
        self.course = course
        self.labs = labs
        self.labWeeks = labWeeks
    }

    mutating func plan() -> [PlannedMove] {
        let siblings = Set(course.children.map(\.name))
        for child in course.children {
            if child.isFile {
                topLevelFile(child)
                continue
            }
            if let standard = CourseFolder(rawValue: child.name) {
                standardFolder(standard, child)
            } else if let legacy = CleanupPlanner.legacyFolder(child.name, siblings: siblings) {
                legacyFolder(legacy, child)
            } else {
                // Course-specific folders such as `대회`: the spec's default is a project.
                let folder = nextFolder(.project)
                moves.append(.init(from: child.name, to: "\(CourseFolder.assignments.rawValue)/\(folder)/\(child.name)", review: .unknownFolder))
            }
        }
        numberLectures()
        return resolveCollisions()
    }

    // MARK: Folders

    mutating func standardFolder(_ folder: CourseFolder, _ node: FolderTree) {
        let base = folder.rawValue
        switch folder {
        case .lectures:
            for item in node.children where !(item.isFile && StandardLayout.isLectureFileName(item.name)) {
                lectureItem(item, at: "\(base)/\(item.name)")
            }
        case .assignments:
            let loose = node.children.filter { $0.isFile || StandardLayout.assignmentFolder($0.name) == nil }
            assignmentItems(loose, in: base, kind: .homework)
        case .exams:
            for item in node.children {
                let path = "\(base)/\(item.name)"
                if item.name == StandardLayout.pastExamsFolder {
                    pastExams(item.children, in: path, source: nil)
                } else if item.isFile || !StandardLayout.isExamFolderName(item.name) {
                    moves.append(.init(from: path, to: "\(base)/\(Keywords.defaultExam)/\(item.name)", review: .guessedExam))
                }
            }
        default:
            break
        }
    }

    mutating func legacyFolder(_ legacy: CleanupPlanner.LegacyFolder, _ node: FolderTree) {
        let base = node.name
        switch legacy {
        case .lectures:
            for item in node.children { lectureItem(item, at: "\(base)/\(item.name)") }
        case .assignments(let kind):
            assignmentItems(node.children, in: base, kind: kind)
        case .labManuals:
            // A manual is what the lab session uses, so it is that week's lecture material (docs/SPEC.md "이름 규칙").
            for item in node.children {
                let path = "\(base)/\(item.name)"
                let lab = Keywords.labNumber(of: item.name, labs: labs) ?? Keywords.assignmentNumber(in: item.name)?.number
                if item.isFile, let week = lab.flatMap({ labWeeks[$0] }) {
                    moves.append(.init(from: path, to: "\(CourseFolder.lectures.rawValue)/\(MaterialIntake.lectureName(item.name, week: week))"))
                } else {
                    lectureItem(item, at: path)
                }
            }
        case .labReports:
            assignmentItems(node.children, in: base, kind: .lab)
        case .pastExams(let source):
            pastExams(node.children, in: base, source: source)
        case .examReview:
            for item in node.children {
                moves.append(.init(from: "\(base)/\(item.name)", to: "\(CourseFolder.exams.rawValue)/\(Keywords.defaultExam)/\(item.name)", review: .guessedExam))
            }
        case .textbooks:
            for item in node.children {
                moves.append(.init(from: "\(base)/\(item.name)", to: "\(CourseFolder.textbooks.rawValue)/\(item.name)"))
            }
        case .notes:
            for item in node.children {
                let from = "\(base)/\(item.name)"
                if item.isFile {
                    let folder = item.name.hasSuffix(".md") ? CourseFolder.notes : .archive
                    moves.append(.init(from: from, to: "\(folder.rawValue)/\(item.name)"))
                } else if containsMarkdown(item) {
                    // Keep note folders and their images together so relative links keep working.
                    moves.append(.init(from: from, to: "\(CourseFolder.notes.rawValue)/\(item.name)", review: .unknownFolder))
                } else {
                    moves.append(.init(from: from, to: "\(CourseFolder.archive.rawValue)/\(item.name)"))
                }
            }
        }
    }

    func containsMarkdown(_ node: FolderTree) -> Bool {
        node.name == StandardLayout.noteAssetsFolder || node.children.contains { $0.isFile ? $0.name.hasSuffix(".md") : containsMarkdown($0) }
    }

    // MARK: Top-level files

    mutating func topLevelFile(_ file: FolderTree) {
        let name = file.name
        let lower = name.lowercased()
        if Keywords.syllabus.contains(where: { lower.contains($0) }) || lower.wholeMatch(of: /ot\..+/) != nil {
            moves.append(.init(from: name, to: "\(CourseFolder.syllabus.rawValue)/\(name)"))
        } else if let role = Keywords.examFiles.first(where: { $0.words.contains { lower.contains($0) } }) {
            let exam = Keywords.examFolder(in: lower)
            let ext = (name as NSString).pathExtension
            moves.append(.init(
                from: name, to: "\(CourseFolder.exams.rawValue)/\(exam ?? Keywords.defaultExam)/\(role.name).\(ext)",
                review: exam == nil ? .guessedExam : nil
            ))
        } else if name.firstMatch(of: /^\d{1,2}[ _]/) != nil {
            lectures.append((name, name))
        } else if Keywords.textbook.contains(where: { lower.contains($0) }) || name.firstMatch(of: /\(.+\)\.[^.]+$/) != nil {
            moves.append(.init(from: name, to: "\(CourseFolder.textbooks.rawValue)/\(name)", review: .guessedFolder))
        } else if name.hasSuffix(".md") {
            moves.append(.init(from: name, to: "\(CourseFolder.notes.rawValue)/\(name)"))
        } else {
            moves.append(.init(from: name, to: "\(CourseFolder.archive.rawValue)/\(name)", review: .unknownFile))
        }
    }

    // MARK: Lectures

    mutating func lectureItem(_ item: FolderTree, at path: String) {
        if item.isFile {
            lectures.append((path, item.name))
        } else {
            moves.append(.init(from: path, to: "\(CourseFolder.lectures.rawValue)/\(item.name)", review: .unknownFolder))
        }
    }

    /// Prefixes the week (`05_`), splitting weeks with several documents into `05-1_`, `05-2_`.
    /// Files sharing a base name (slides.pdf, slides.pptx) share a prefix.
    mutating func numberLectures() {
        var parsed = lectures.map { item in (item, Keywords.week(in: item.name)) }
        var next = (parsed.compactMap { $0.1?.week }.max() ?? 0) + 1
        for i in parsed.indices.sorted(by: { parsed[$0].0.name < parsed[$1].0.name }) where parsed[i].1 == nil {
            parsed[i].1 = (next, nil, .unknownWeek)
            next += 1
        }
        let byWeek = Dictionary(grouping: parsed, by: { $0.1!.week })
        for (week, items) in byWeek {
            let bases = Set(items.map { Keywords.title(of: $0.0.name, stripping: $0.1!.leading).base }).sorted()
            for (item, parse) in items {
                let (base, ext) = Keywords.title(of: item.name, stripping: parse!.leading)
                let sub = bases.count > 1 ? "-\(bases.firstIndex(of: base)! + 1)" : ""
                let name = String(format: "%02d", week) + sub + "_" + base + ext
                moves.append(.init(from: item.path, to: "\(CourseFolder.lectures.rawValue)/\(name)", review: parse!.review))
            }
        }
    }

    // MARK: Assignments

    mutating func assignmentItems(_ items: [FolderTree], in base: String, kind: AssignmentKind) {
        let root = CourseFolder.assignments.rawValue
        for item in items {
            let from = "\(base)/\(item.name)"
            let itemKind = item.name.lowercased().firstMatch(of: /lab\s*\d/) != nil ? AssignmentKind.lab : kind
            // An experiment's name beats any number in the file name: `2_<id>_VSEPR.pdf` is not Lab02.
            let lab = itemKind == .lab ? Keywords.labNumber(of: item.name, labs: labs) : nil
            let parsed = lab.map { (number: $0, review: ReviewReason?.none) } ?? Keywords.assignmentNumber(in: item.name)
            switch (parsed, item.content) {
            case (let p?, .folder(let children)):
                // `Assignment 1/` becomes `HW01/`: its contents move, the folder name carries no other information.
                let folder = itemKind.rawValue + String(format: "%02d", p.number)
                moves += children.map { .init(from: "\(from)/\($0.name)", to: "\(root)/\(folder)/\($0.name)", review: p.review) }
            case (let p?, _):
                let folder = itemKind.rawValue + String(format: "%02d", p.number)
                moves.append(.init(from: from, to: "\(root)/\(folder)/\(item.name)", review: p.review))
            case (nil, .opaque):
                moves.append(.init(from: from, to: "\(root)/\(nextFolder(.project))/\(item.name)", review: .unknownNumber))
            case (nil, _):
                moves.append(.init(from: from, to: "\(root)/\(itemKind.rawValue)00/\(item.name)", review: .unknownNumber))
            }
        }
    }

    /// Next unused `<prefix><NN>` under Assignments, counting both existing and planned folders.
    func nextFolder(_ kind: AssignmentKind) -> String {
        let existing = course[child: CourseFolder.assignments.rawValue]?.children.map(\.name) ?? []
        let planned = moves.compactMap { $0.to.split(separator: "/").dropFirst().first.map(String.init) }
        let used = (existing + planned).compactMap { StandardLayout.assignmentFolder($0) }
            .filter { $0.prefix == kind.rawValue }.map(\.number)
        return kind.rawValue + String(format: "%02d", (used.max() ?? 0) + 1)
    }

    // MARK: Past exams

    mutating func pastExams(_ items: [FolderTree], in base: String, source: String?) {
        let target = "\(CourseFolder.exams.rawValue)/\(StandardLayout.pastExamsFolder)"
        for item in items {
            let from = "\(base)/\(item.name)"
            guard item.isFile else {
                moves.append(.init(from: from, to: "\(target)/\(item.name)", review: .unknownFolder))
                continue
            }
            if source == nil, StandardLayout.isPastExamFileName(item.name) {
                moves.append(.init(from: from, to: "\(target)/\(item.name)"))
            } else if let renamed = Keywords.pastExamName(item.name, source: source) {
                moves.append(.init(from: from, to: "\(target)/\(renamed)"))
            } else {
                moves.append(.init(from: from, to: "\(target)/\(item.name)", review: .pastExamNameKept))
            }
        }
    }

    // MARK: Collisions

    /// Two items aimed at one path, or at a path that stays occupied, get ` (2)`, ` (3)`, ...
    func resolveCollisions() -> [PlannedMove] {
        let sources = Set(moves.map(\.from))
        var taken = Set(allPaths(course, "").filter { path in !sources.contains { path == $0 || path.hasPrefix($0 + "/") } })
        return moves.sorted { $0.from < $1.from }.map { move in
            var move = move
            guard taken.contains(move.to) else {
                taken.insert(move.to)
                return move
            }
            let ns = move.to as NSString
            let stem = ns.deletingPathExtension, ext = ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension
            var n = 2
            while taken.contains("\(stem) (\(n))\(ext)") { n += 1 }
            move.to = "\(stem) (\(n))\(ext)"
            move.review = .nameCollision
            taken.insert(move.to)
            return move
        }
    }

    func allPaths(_ node: FolderTree, _ base: String) -> [String] {
        node.children.flatMap { child -> [String] in
            let path = base.isEmpty ? child.name : "\(base)/\(child.name)"
            return [path] + allPaths(child, path)
        }
    }
}

enum Keywords {
    static let syllabus = ["syllabus", "강의계획서", "수업계획서", "orientation", "스케줄", "schedule", "클리닉", "clinic"]
    static let textbook = ["textbook", "교재", "edition", "solution manual", "introduction to"]
    static let examFiles: [(name: String, words: [String])] = [
        ("Guideline", ["guideline", "시험 안내", "시험안내"]),
        ("Seating", ["seating", "자리", "좌석"]),
    ]

    static var midterm: Regex<Substring> { #/mid[\s_-]?term|midterm|mid|중간고사|중간/# }
    static var final: Regex<Substring> { #/final[\s_-]?(?:term|exam)|final|기말고사|기말/# }
    static var quiz: Regex<Substring> { #/quiz|퀴즈/# }

    /// When the target exam is unknown, material goes to the midterm folder and is flagged.
    static let defaultExam = ExamKind.midterm.folderName()!

    static func examFolder(in lower: String) -> String? {
        if lower.contains(midterm) { return ExamKind.midterm.folderName() }
        if lower.contains(final) { return ExamKind.final.folderName() }
        return nil
    }

    /// Week, the leading number to strip from the title (when the week came from it), and why it needs review.
    static func week(in name: String) -> (week: Int, leading: Bool?, review: ReviewReason?)? {
        let lower = name.lowercased()
        if let m = lower.firstMatch(of: /(?:week|wk)[\s_-]*(\d{1,2})(?!\d)/) ?? lower.firstMatch(of: /(\d{1,2})\s*주차/) {
            return (Int(m.1)!, false, nil)
        }
        if let m = lower.firstMatch(of: /^(\d{1,2})[\s_.-]/) {
            return (Int(m.1)!, true, .guessedWeek)
        }
        if let m = lower.firstMatch(of: /(?:lecture|lec|chapter|ch)[\s_-]*(\d{1,2})(?!\d)/) {
            return (Int(m.1)!, false, .guessedWeek)
        }
        return nil
    }

    static func title(of name: String, stripping leading: Bool?) -> (base: String, ext: String) {
        let ns = name as NSString
        var base = ns.deletingPathExtension
        if leading == true, let m = base.firstMatch(of: /^\d{1,2}[\s_.-]+/) {
            base.removeSubrange(m.range)
        }
        return (base, ns.pathExtension.isEmpty ? "" : "." + ns.pathExtension)
    }

    /// Number of the experiment sharing the most with `name`; nil when none, or tied between different numbers.
    /// Shared words are weighted by length: `recrystallization` says more than `point`.
    static func labNumber(of name: String, labs: [String: Int]) -> Int? {
        let file = words(name)
        let scores = labs.map { (number: $0.value, score: words($0.key).intersection(file).reduce(0) { $0 + $1.count }) }
        guard let best = scores.map(\.score).max(), best > 0 else { return nil }
        let numbers = Set(scores.filter { $0.score == best }.map(\.number))
        return numbers.count == 1 ? numbers.first : nil
    }

    static let labStopWords: Set<String> = ["and", "of", "the", "a", "an", "in", "using", "lab", "pre", "prelab", "report", "manual", "pdf"]

    static func words(_ text: String) -> Set<String> {
        let lower = (text as NSString).deletingPathExtension.lowercased().replacingOccurrences(of: "&", with: " and ")
        return Set(lower.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
            .filter { !labStopWords.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    static func assignmentNumber(in name: String) -> (number: Int, review: ReviewReason?)? {
        let lower = name.lowercased()
        let keyword = /(?:hw|homework|assignment|assign|pa|lab|sp|slow[\s_-]?problems?|report|project|과제|숙제)[\s_-]*(\d{1,2})(?!\d)/
        if let m = lower.firstMatch(of: keyword) ?? lower.firstMatch(of: /\d{2}h(\d{1,2})(?!\d)/) {
            return (Int(m.1)!, nil)
        }
        if let m = lower.firstMatch(of: /^(\d{1,2})[\s_.-]/) {
            return (Int(m.1)!, .guessedNumber)
        }
        return nil
    }

    /// `<year> <Midterm|Final|Quiz> (<source>)[ Solution].<ext>`, or nil if anything else in the name would be lost.
    static func pastExamName(_ name: String, source: String?) -> String? {
        let ns = name as NSString
        var rest = ns.deletingPathExtension.lowercased()
        guard let year = rest.firstMatch(of: /20\d{2}/).map({ String($0.output) }) else { return nil }
        rest.replace(year, with: "")
        let kinds: [(String, Regex<Substring>)] = [
            (ExamKind.midterm.folderName()!, midterm), (ExamKind.final.folderName()!, final), (StandardLayout.quizFolderPrefix, quiz),
        ]
        guard let (kind, regex) = kinds.first(where: { rest.contains($0.1) }) else { return nil }
        rest.replace(regex, with: "")
        let solution = rest.contains(/sol(?:ution)?s?|answers?|해설|답안?/)
        rest.replace(/sol(?:ution)?s?|answers?|해설|답안?/, with: "")
        guard rest.replacing(/[\s_\-.()\[\]]/, with: "").isEmpty else { return nil }
        let src = source.map { " (\($0))" } ?? ""
        return "\(year) \(kind)\(src)\(solution ? " Solution" : "").\(ns.pathExtension)"
    }
}
