import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension ProblemCommand {
    struct Collect: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .problemCollectAbstract), discussion: String(localized: .problemCollectDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .commonHelpCourse), valueName: "course"), completion: Complete.ref(.course))
        var course: String = ""
        @Option(
            name: .customLong("set"), help: ArgumentHelp(String(localized: .problemCollectHelpSet), valueName: "set"),
            completion: Complete.ref(.problemSet))
        var sets: [String] = []
        @Flag(help: ArgumentHelp(String(localized: .problemCollectHelpOverwrite))) var overwrite = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let ids = try sets.map { try r.id(.problemSet, $0, in: c) }
            var pdfs: (problems: URL, solutions: URL)?
            // 다시 그린 그림이 있으면 여기서 PDF로 그려 빌드한다. 액션은 WebKit 없이 빌드하므로 그대로 두면 자른 그림만 들어간다.
            if !g.dryRun {
                let store = try ctx.store(c.id), file = try ctx.file(c.id)
                var art: [UUID: ProblemCollectionFiles.Art] = [:]
                for (id, doc) in store.problemArt() {
                    let a = ProblemCollectionFiles.Art(
                        figure: doc.model.figure.flatMap(PageRender.figurePDF),
                        solution: doc.model.solutionFigure.flatMap(PageRender.figurePDF))
                    if a.figure != nil || a.solution != nil { art[id] = a }
                }
                if !art.isEmpty {
                    let files = ProblemCollectionFiles(
                        store: store, file: file, semester: try ctx.semester(of: file.course), author: try ctx.settings().study.coverName,
                        sets: ids, art: art)
                    if files.collection.problemCount > 0 { pdfs = try files.build(at: ctx.now, calendar: ctx.calendar) }
                }
            }
            try perform(
                spec: ProblemCollectionBuild(
                    course: c.id, sets: ids, problems: [], pdf: pdfs?.problems.path, solutionsPDF: pdfs?.solutions.path,
                    overwrite: overwrite), g, ctx: ctx)
        }
    }
}
