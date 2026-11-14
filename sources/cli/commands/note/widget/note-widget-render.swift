import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand.Widget {
    struct Render: ParsableCommand, HandRead {
        static let reason = "그려 보기는 FolioCLI의 화면 밖 WKWebView(PageRender)로 그린다"
        static let panel = true
        static let configuration = CommandConfiguration(
            abstract: String(localized: .noteWidgetRenderAbstract), discussion: String(localized: .noteRenderDiscussion))
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpWidget), valueName: "widget")) var widget: String = ""
        @Option(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpText), valueName: "html")) var text: String?
        @Option(help: ArgumentHelp(String(localized: .noteWidgetRenderHelpFile), valueName: "file"), completion: .file()) var html: String?
        @OptionGroup var out: RenderOutput

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let given = try text ?? html.map(readText)
            var course: CourseRef?
            var ref = ""
            if given != nil, !widget.isEmpty, !widget.contains("/") {
                course = try r.course(widget)
            } else if !widget.isEmpty || given == nil {
                (course, ref) = try r.split(widget)
            }
            let source: (label: String, text: String)
            if let given {
                source = (html.map { URL(filePath: $0).deletingPathExtension().lastPathComponent } ?? "widget", given)
            } else {
                guard let c = course, !ref.isEmpty else {
                    throw CLIError(exit: .usage, message: String(localized: .noteWidgetRenderNothing))
                }
                let id = try r.widget(ref, in: c)
                source = (String(id.uuidString.prefix(8)), try reporting { try MaterialText.read(c.store, NoteWidget.path(id)) })
            }
            try out.report(
                try PageRender.widget(source.text, accent: course?.color ?? CourseColor.neutral, widths: out.sizes),
                label: source.label, json: g.json)
        }
    }
}
