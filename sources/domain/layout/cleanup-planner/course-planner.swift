import Foundation

struct CoursePlanner {
    let course: FolderTree
    let labs: [String: Int]
    let labWeeks: [Int: Int]
    let selfMade: Set<String>
    let exams: [Exam]?
    var moves: [PlannedMove] = []
    var removals: [String] = []
    var lectures: [(path: String, name: String)] = []

    init(course: FolderTree, labs: [String: Int] = [:], labWeeks: [Int: Int] = [:], selfMade: Set<String> = [], exams: [Exam]? = nil) {
        self.course = course
        self.labs = labs
        self.labWeeks = labWeeks
        self.selfMade = selfMade
        self.exams = exams
    }

    // 새 시험은 제목으로 폴더 이름을 정하므로(`중간고사`), 짐작한 이름을 각 시험의 폴더와 제목에 맞춰 본다. 정리
    // 적용은 폴더로 연결하므로, 없는 시험을 가리키는 계획은 적용할 때 버려질 연결을 보이게 된다. 그래서 맞는 시험이
    // 없으면 nil이다.
    func examLink(_ guess: String?) -> String? {
        guard let guess, let exams else { return guess }
        let named = exams.filter { $0.folder != nil }
        if named.contains(where: { $0.folder == guess }) { return guess }
        return named.first { e in [e.folder, e.title].compactMap { $0 }.contains { Keywords.examFolder(in: $0.lowercased()) == guess } }?
            .folder
    }

    func examFolder(_ guess: String?) -> String {
        let name = guess ?? Keywords.defaultExam
        return examLink(name) ?? name
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
                let folder = nextFolder(.project)
                moves.append(
                    .init(from: child.name, to: "\(CourseFolder.assignments.rawValue)/\(folder)/\(child.name)", review: .unknownFolder))
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
                if item.name == StandardLayout.legacyPastExamsFolder {
                    pastExams(item.children, in: path, source: nil)
                } else if item.isFile {
                    // 레이아웃 검사가 지키듯이 여기 있는 폴더는 모두 제목으로 이름을 정한 시험 자신의 폴더이므로, 낱개 파일만
                    // 시험으로 보낸다. 폴더가 어느 시험의 것인지는 트리만으로 알 수 없다.
                    moves.append(.init(from: path, to: "\(base)/\(examFolder(nil))/\(item.name)", review: .guessedExam))
                } else if case .folder(let files) = item.content {
                    if files.isEmpty { removals.append(path) }
                    for file in files where file.isFile && Keywords.looksSelfMade(file.name) {
                        moves.append(
                            .init(
                                from: "\(path)/\(file.name)", to: "\(CourseFolder.study.rawValue)/\(file.name)",
                                review: .guessedOrigin, exam: examLink(item.name)))
                    }
                }
            }
        case .exercises:
            // 예전 규칙이 `Exam Review`를 통째로 여기 옮겼다. 그런 곳에서는 기록이 직접 만든 파일을 알려 주고, 그 옆의 나머지는
            // 교수가 준 것과 구분할 수 없으므로 제안만 한다.
            guard node.children.contains(where: { selfMade.contains("\(base)/\($0.name)") }) else { break }
            for item in node.children {
                let path = "\(base)/\(item.name)"
                let to = "\(CourseFolder.study.rawValue)/\(item.name)"
                if selfMade.contains(path) {
                    moves.append(
                        .init(from: path, to: to, exam: examLink(Keywords.examFolder(in: item.name.lowercased()) ?? Keywords.defaultExam)))
                } else {
                    moves.append(.init(from: path, to: to, review: .guessedOrigin))
                }
            }
        case .notes:
            if let exports = node[child: StandardLayout.legacyNoteExportsFolder], !exports.isFile {
                for item in exports.children {
                    moves.append(.init(from: "\(base)/\(exports.name)/\(item.name)", to: "\(CourseFolder.study.rawValue)/\(item.name)"))
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
            for item in node.children {
                let path = "\(base)/\(item.name)"
                let lab = Keywords.labNumber(of: item.name, labs: labs) ?? Keywords.assignmentNumber(in: item.name)?.number
                if item.isFile, let week = lab.flatMap({ labWeeks[$0] }) {
                    moves.append(
                        .init(from: path, to: "\(CourseFolder.lectures.rawValue)/\(MaterialIntake.lectureName(item.name, week: week))"))
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
                moves.append(
                    .init(
                        from: "\(base)/\(item.name)", to: "\(CourseFolder.study.rawValue)/\(item.name)",
                        exam: examLink(Keywords.examFolder(in: item.name.lowercased()) ?? Keywords.defaultExam)))
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
                    // 상대 링크가 계속 맞도록 노트 폴더와 그 그림을 함께 둔다.
                    moves.append(.init(from: from, to: "\(CourseFolder.notes.rawValue)/\(item.name)", review: .unknownFolder))
                } else {
                    moves.append(.init(from: from, to: "\(CourseFolder.archive.rawValue)/\(item.name)"))
                }
            }
        }
    }

    func containsMarkdown(_ node: FolderTree) -> Bool {
        node.name == StandardLayout.noteAssetsFolder
            || node.children.contains { $0.isFile ? $0.name.hasSuffix(".md") : containsMarkdown($0) }
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
            moves.append(
                .init(
                    from: name, to: "\(CourseFolder.exams.rawValue)/\(examFolder(exam))/\(role.name).\(ext)",
                    review: exam == nil ? .guessedExam : nil
                ))
        } else if Keywords.looksSelfMade(name) {
            moves.append(
                .init(
                    from: name, to: "\(CourseFolder.study.rawValue)/\(name)", review: .guessedOrigin,
                    exam: examLink(Keywords.examFolder(in: lower))))
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
            // 실험 이름이 파일 이름의 번호보다 앞선다. `2_<id>_VSEPR.pdf`는 Lab02가 아니다.
            let lab = itemKind == .lab ? Keywords.labNumber(of: item.name, labs: labs) : nil
            let parsed = lab.map { (number: $0, review: ReviewReason?.none) } ?? Keywords.assignmentNumber(in: item.name)
            switch (parsed, item.content) {
            case (let p?, .folder(let children)):
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

    func nextFolder(_ kind: AssignmentKind) -> String {
        let existing = course[child: CourseFolder.assignments.rawValue]?.children.map(\.name) ?? []
        let planned = moves.compactMap { $0.to.split(separator: "/").dropFirst().first.map(String.init) }
        let used = (existing + planned).compactMap { StandardLayout.assignmentFolder($0) }
            .filter { $0.prefix == kind.rawValue }.map(\.number)
        return kind.rawValue + String(format: "%02d", (used.max() ?? 0) + 1)
    }

    // MARK: Past exams

    mutating func pastExams(_ items: [FolderTree], in base: String, source: String?) {
        let target = ([CourseFolder.inherited.rawValue] + (source.map { [$0] } ?? [])).joined(separator: "/")
        for item in items {
            moves.append(.init(from: "\(base)/\(item.name)", to: "\(target)/\(item.name)", kind: item.isFile ? .pastExam : nil))
        }
    }

    // MARK: Collisions

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
