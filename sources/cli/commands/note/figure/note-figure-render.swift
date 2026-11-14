import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Figure {
    struct Render: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteFigureRenderAbstract), discussion: String(localized: .noteRenderDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(
            help: ArgumentHelp(String(localized: .noteRenderHelpCourse), valueName: "course"), completion: .custom(Complete.courses))
        var course: String = ""
        @Argument(help: ArgumentHelp(String(localized: .noteFigureHelpName), valueName: "name")) var name: String?
        @Option(help: ArgumentHelp(String(localized: .noteFigureRenderHelpText), valueName: "svg")) var text: String?
        @Option(help: ArgumentHelp(String(localized: .noteFigureRenderHelpFile), valueName: "file"), completion: .file()) var svg: String?
        @OptionGroup var out: RenderOutput

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try course.isEmpty && (text != nil || svg != nil) ? nil : r.course(course)
            let source: (label: String, text: String)
            if let text {
                source = ("figure", text)
            } else if let svg {
                source = (URL(filePath: svg).deletingPathExtension().lastPathComponent, try readText(svg))
            } else {
                guard let c, let name else { throw CLIError(exit: .usage, message: String(localized: .noteFigureRenderNothing)) }
                let (file, read) = try readFigure(c, name)
                source = ((file as NSString).deletingPathExtension, read)
            }
            try out.report(
                try PageRender.figure(source.text, accent: c?.color ?? CourseColor.neutral, widths: out.sizes), label: source.label,
                json: g.json)
        }
    }
}
