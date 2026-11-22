import FolioDomain
import FolioStorage
import Foundation

// 문제집 하나를 빌드할 폴더와 그 안의 파일이다. `.tex`와 잘라 올 문제지 PDF의 사본은 과목 폴더가 아니라 임시 폴더에 둔다.
// Study에는 두 PDF만 두기 위해서다. 앱은 컴파일을 화면 밖에서 하고 만든 PDF를 `ProblemCollectionBuild`에 넘긴다.
public struct ProblemCollectionFiles: Sendable {
    public let collection: ProblemCollection
    // 빌드 폴더 안의 이름과 원래 문제지 PDF다.
    public let sheets: [String: URL]
    // 빌드 폴더 안의 이름과 다시 그린 그림의 PDF다.
    let figures: [String: Data]
    public let folder: URL
    let code: String

    public init(
        store: CourseStore, file: CourseFile, semester: Semester?, author: String, problems: [UUID] = [], sets: [UUID] = [],
        art: [UUID: Art] = [:]
    ) {
        // 과목 폴더 이름은 `<대표 과목코드> <과목명>`이다. 영어 이름이 있으면 표지에 그것을 쓴다.
        let name = store.url.lastPathComponent
        code = name.split(separator: " ").first.map(String.init) ?? name
        let english = file.course.titleEn.trimmingCharacters(in: .whitespaces)
        let title = english.isEmpty ? file.course.title : english
        let chosen = file.problemSets.filter { sets.isEmpty || sets.contains($0.id) }
        let picked = problems.isEmpty ? Set(chosen.flatMap(\.problems).map(\.id)) : Set(problems)

        // 그림이 있는 묶음만 문제지를 빌드 폴더에 복사한다. 경로에 공백과 한글이 있어도 graphicx가 읽도록 이름을 새로 짓는다.
        var sheets: [String: URL] = [:], names: [UUID: String] = [:]
        for set in chosen {
            guard let id = set.materialId, let m = file.materials.first(where: { $0.id == id && $0.isPDF }) else { continue }
            let figured = ProblemCollection.sections(sets: [set], picked: picked).flatMap(\.items).contains { item in
                switch item {
                case .stem(let g): !g.figures.isEmpty
                case .problem(let p): !p.figures.isEmpty
                }
            }
            guard figured else { continue }
            let built = "sheet-\(sheets.count + 1).pdf"  // strings: data, 빌드 폴더 안의 파일 이름
            sheets[built] = store.fileURL(m.path)
            names[set.id] = built
        }
        self.sheets = sheets

        var figures: [String: Data] = [:], arts: [UUID: ProblemCollection.Art] = [:]
        for (id, a) in art {
            var named = ProblemCollection.Art()
            if let pdf = a.figure {
                let built = "art-\(id.uuidString).pdf"  // strings: data, 빌드 폴더 안의 파일 이름
                named.figure = built
                figures[built] = pdf
            }
            if let pdf = a.solution {
                let built = "art-\(id.uuidString)-solution.pdf"  // strings: data, 빌드 폴더 안의 파일 이름
                named.solution = built
                figures[built] = pdf
            }
            if named.figure != nil || named.solution != nil { arts[id] = named }
        }
        self.figures = figures
        collection = ProblemCollection(
            course: "\(code) \(title)",
            term: semester.flatMap { ProblemCollection.term(year: $0.year, $0.term) },
            author: author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : author,
            sections: ProblemCollection.sections(sets: chosen, picked: picked, sheets: names), art: arts)
        folder = TexOutput.folder(for: store.url.appending(path: CourseFolder.study.rawValue))
    }

    // 문제나 지문 하나의 다시 그린 그림(`ProblemArt`)을 PDF로 그린 것이다. SVG를 PDF로 그리는 일은 WebKit이 하므로 앱과
    // CLI가 그려서 넘긴다. 넘기지 않은 항목은 문제지에서 자른 그림을 쓴다.
    public struct Art: Sendable {
        public var figure: Data?
        public var solution: Data?

        public init(figure: Data? = nil, solution: Data? = nil) {
            self.figure = figure
            self.solution = solution
        }
    }

    var problemsName: String { "\(code)-Practice-Problems" }  // strings: data, 파일 이름
    var solutionsName: String { "\(code)-Practice-Solutions" }  // strings: data, 파일 이름
    // 손으로 푼 문제집을 Study에 들여올 때의 이름이다. 같은 이름이 있으면 들여오기가 " 2"를 붙인다.
    public var answersFileName: String { "\(code)-Practice-Answers.pdf" }  // strings: data, 파일 이름

    public var problemsPath: String { "\(CourseFolder.study.rawValue)/\(problemsName).pdf" }
    public var solutionsPath: String { "\(CourseFolder.study.rawValue)/\(solutionsName).pdf" }

    public var problemsTeX: URL { folder.appending(path: problemsName + ".tex") }
    public var solutionsTeX: URL { folder.appending(path: solutionsName + ".tex") }

    // 두 `.tex`를 쓰고 Tectonic으로 컴파일한다. 몇 초가 걸리므로 앱은 화면 밖에서 부른다.
    public func build(at now: Date, calendar: Calendar) throws -> (problems: URL, solutions: URL) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(collection.problemsTeX.utf8).write(to: problemsTeX, options: .atomic)
        try Data(collection.solutionsTeX.utf8).write(to: solutionsTeX, options: .atomic)
        for (name, source) in sheets {
            let target = folder.appending(path: name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        }
        for (name, pdf) in figures { try pdf.write(to: folder.appending(path: name), options: .atomic) }
        return (
            try MaterialBuild.compile(problemsTeX, now, calendar), try MaterialBuild.compile(solutionsTeX, now, calendar)
        )
    }
}
