import AppKit
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import Folio

/// Every app link a note or a file can hold (#347): each `AppLink` kind with each anchor and page it takes, written
/// each way (`Form`), opened from each view that shows it (`Surface`). Each cell checks the name the view shows, when
/// it shows one, and that the click hands `\.openLink` the link written, which the workspace finds and a screen draws.
///
/// The samples come from `AppLink.Kind.allCases` and the forms and surfaces from their own `allCases`, and every
/// switch below has no default: a new kind, form or surface doesn't compile, or fails here, until it is covered or
/// says why it can't be, as the action coverage check does for actions.
@MainActor @Suite(.serialized)
struct AppLinkCoverageTests {
    enum Form: CaseIterable {
        /// `[[<kind>:<ID>#…|이름]]`, as link completion writes it.
        case objectWiki
        /// `[[folio://<kind>/<ID>#…|이름]]`, a copied address between brackets.
        case addressWiki
        /// A bare `folio://…` in a note.
        case bare
        /// `[이름](folio://…)`.
        case markdown
        /// `\href{folio://…}{이름}` in a `.tex`.
        case texHref
        /// `folio://…` in a code or text file, in a comment or a string.
        case textFile
    }

    enum Surface: CaseIterable {
        /// A markdown note's preview, clicked.
        case preview
        /// A markdown note's edit view, ⌘-clicked.
        case editor
        /// The PDF a `.tex` builds, clicked.
        case texPDF
        /// The editor for `.tex`, code and text files, ⌘-clicked.
        case textEditor
    }

    enum Cell: Equatable {
        case covered
        case notApplicable(String)
    }

    /// The table of forms and surfaces.
    static func cell(_ form: Form, _ surface: Surface) -> Cell {
        switch (form, surface) {
        case (.objectWiki, .preview), (.objectWiki, .editor), (.addressWiki, .preview), (.addressWiki, .editor),
             (.bare, .preview), (.bare, .editor), (.markdown, .preview), (.markdown, .editor):
            .covered
        case (.texHref, .preview), (.texHref, .editor):
            .notApplicable("A note is markdown: a .tex shows as the PDF it builds (texPDF) and its source (textEditor)")
        case (.textFile, .preview), (.textFile, .editor):
            .notApplicable("A code or text file opens in the text editor, not as a note")
        case (.objectWiki, .texPDF), (.addressWiki, .texPDF), (.bare, .texPDF), (.markdown, .texPDF), (.textFile, .texPDF):
            .notApplicable("A PDF built from TeX links only what \\href wrote; the rest is typeset text")
        case (.texHref, .texPDF), (.texHref, .textEditor), (.textFile, .textEditor), (.addressWiki, .textEditor), (.markdown, .textEditor):
            .covered
        case (.objectWiki, .textEditor):
            .notApplicable("`[[<kind>:<ID>]]` is a note's syntax; a text file opens addresses only")
        case (.bare, .textEditor):
            .notApplicable("A bare address in a text file is the textFile form")
        }
    }

    /// Whether the surface shows a name of its own for a link. The edit views show the source as written, and a built
    /// PDF the text the author typeset, so only the preview names what a link points at.
    static func showsName(_ surface: Surface) -> Bool {
        switch surface {
        case .preview: true
        case .editor, .texPDF, .textEditor: false
        }
    }

    // MARK: Samples

    struct Sample {
        var link: AppLink
        var screen: Screen
    }

    /// One of each kind in the fixture folder, with each anchor it takes, and every course page and settings tab.
    static func samples(_ workspace: Workspace) throws -> [Sample] {
        let course = graphTheory
        let fixture = try Fixtures(workspace)
        var out: [Sample] = []
        for kind in AppLink.Kind.allCases {
            let place: Screen? = switch kind {
            case .today: .today
            case .grades: .grades
            case .requirements: .requirements
            case .people: .people
            case .codes: .codes
            case .settings: .settings
            case .whatsNew: .whatsNew
            case .proposals: .proposals
            case .semester, .course, .session, .unit, .note, .material, .assignment, .exam, .card, .problemSet, .person, .recording: nil
            }
            if let place {
                out.append(Sample(link: .place(kind), screen: place))
                continue
            }
            let id: UUID = switch kind {
            case .semester: fixture.semester
            case .course: course
            case .session: fixture.session
            case .unit: fixture.unit
            case .note: fixture.note
            case .material: fixture.material
            case .assignment: fixture.assignment
            case .exam: fixture.exam
            case .card: fixture.card
            case .problemSet: fixture.problemSet
            case .person: fixture.person
            case .recording: fixture.recording
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals: preconditionFailure()
            }
            let screen: Screen = switch kind.home {
            case .app: preconditionFailure()
            case .transcript: .semester(id)
            case .catalog: .people
            case .course, .quiz: .course(course)
            }
            let base = AppLink(kind, id)
            out.append(Sample(link: base, screen: screen))
            for anchor in kind.anchors.sorted(by: { "\($0)" < "\($1)" }) {
                let value: AppLink.Anchor = switch anchor {
                case .page: .page(2)
                case .block: .block("c1")
                case .heading: .heading("정의 모음")
                case .time: .time(750)
                }
                out.append(Sample(link: base.with(value), screen: screen))
            }
        }
        for page in AppLink.CoursePage.allCases where page != .overview {
            out.append(Sample(link: .course(course, page: page), screen: .course(course)))
        }
        for tab in AppLink.SettingsPage.allCases {
            out.append(Sample(link: .settings(tab), screen: .settings))
        }
        return out
    }

    /// Something of every kind a link names by ID, in 그래프 이론 or the folder's tables.
    @MainActor struct Fixtures {
        var semester, session, unit, note, material, assignment, exam, card, problemSet, person, recording: UUID

        init(_ workspace: Workspace) throws {
            let course = graphTheory
            semester = try #require(workspace.transcript.semesters.first).id
            session = try #require(workspace.run(SessionAdd(course: course, date: .now))?.made)
            unit = try #require(workspace.run(UnitAdd(course: course, title: "매칭"))?.made)
            note = try #require(workspace.run(NoteAdd(course: course, title: "매칭 정리", body: "# 정의 모음\n\n첫 정리 ^c1\n"))?.made)
            workspace.run(MaterialTrack(course: course))
            material = try #require(workspace.course(course)?.file.materials.first).id
            assignment = try #require(workspace.run(AssignmentAdd(course: course, title: "HW03"))?.made)
            exam = try #require(workspace.run(ExamAdd(course: course, title: "중간고사"))?.made)
            let quiz = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
            workspace.run(QuizCardSave(course: course, cards: [quiz]))
            card = quiz.id
            let set = ProblemSet(device: workspace.device, at: .now, title: "Exercise 1", problems: [.init(number: "1")])
            workspace.run(ProblemSetSave(course: course, set: set))
            problemSet = set.id
            var catalog = workspace.catalog
            let someone = Person(device: workspace.device, at: .now, name: "김교수")
            catalog.people.append(someone)
            workspace.run(CatalogSet(catalog: catalog))
            person = someone.id
            let take = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a")
            try ActionContext(gist: try #require(workspace.gist), device: workspace.device).edit(course) { $0.recordings = [take] }
            workspace.reload()
            recording = take.id
        }
    }

    // MARK: Writing

    /// A link written in a form: the text, and where in it a click lands on the link. A text file's editor colors
    /// nothing as a link and opens the address under the click, so there the click lands on the address.
    struct Written {
        var text: String
        var at: Int
        var address: Int? = nil
    }

    static let alias = "보기"

    /// How `form` writes `link`, or why it can't. `named` adds `|이름` to a wiki link.
    static func write(_ link: AppLink, _ form: Form, named: Bool) -> Result<Written, Unwritable> {
        let address = link.string
        func around(_ body: String) -> Written {
            let before = "앞 "
            return Written(text: before + body + " 뒤", at: before.utf16.count + 3)
        }
        switch form {
        case .objectWiki:
            guard let id = link.id else { return .failure(Unwritable("A place has no ID; it goes between brackets as its address")) }
            guard link.page == nil, link.settingsPage == nil else {
                return .failure(Unwritable("A course's page has no <kind>:<ID> form; it goes between brackets as its address"))
            }
            let fragment: String? = switch link.anchor {
            case .page(let n): "page=\(n)"
            case .block(let b): "^" + b
            case .heading(let h): h
            case .time(let t): "t=" + AppLink.clock(t)
            case nil: nil
            }
            return .success(around(WikiLink.written(link.kind.rawValue, id, fragment: fragment, alias: named ? alias : nil)))
        case .addressWiki:
            return .success(around(WikiLink.written(address: address, alias: named ? alias : nil)))
        case .bare:
            return .success(around(address))
        case .markdown:
            return .success(Written(text: "앞 [\(alias)](\(address)) 뒤", at: "앞 [".utf16.count + 1, address: "앞 [\(alias)](".utf16.count + 3))
        case .texHref:
            return .success(Written(text: "See \\href{\(address)}{link}.\n", at: "See \\href{".utf16.count + 3))
        case .textFile:
            return .success(Written(text: "// 참고: \(address)\nlet x = 1\n", at: "// 참고: ".utf16.count + 3))
        }
    }

    struct Unwritable: Error, Equatable {
        var reason: String
        init(_ reason: String) { self.reason = reason }
    }

    // MARK: Opening

    /// What a surface shows for the link in `written` and what its click opens.
    struct Shown {
        var name: String?
        var opened: AppLink?
    }

    @MainActor final class Views {
        let workspace: Workspace
        let embeds: NoteEmbeds
        let editor: SourceTextView
        let editorWindow: NSWindow
        let text: SourceFileTextView
        let textWindow: NSWindow
        var opened: AppLink?
        let click: NSEvent

        init(_ workspace: Workspace) throws {
            self.workspace = workspace
            let course = try #require(workspace.course(graphTheory))
            embeds = NoteEmbedSource(workspace: workspace, course: course, own: nil).embeds(revision: workspace.notesRevision, text: "")
            (editor, editorWindow) = NoteSourceTests.editor("")
            final class Box { var text = "" }
            let box = Box()
            let source = SourceFileEditor(text: Binding(get: { box.text }, set: { box.text = $0 }), language: "latex", reveal: .constant(nil))
            let scroll = source.makeView(source.makeCoordinator())
            text = try #require(scroll.documentView as? SourceFileTextView)
            textWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            scroll.frame = textWindow.contentView!.bounds
            textWindow.contentView!.addSubview(scroll)
            click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let open = OpenLinkAction { [unowned self] link, _, _ in opened = link }
            editor.linkOpener = open
            text.linkOpener = open
        }

        var opener: OpenLinkAction { OpenLinkAction { [unowned self] link, _, _ in opened = link } }

        func show(_ written: Written, on surface: Surface) -> Shown {
            opened = nil
            switch surface {
            case .preview:
                let html = HTMLRenderer.blocks(ParsedNote(written.text), embeds: embeds).map(\.html).joined()
                guard let m = html.firstMatch(of: /<a [^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/) else { return Shown() }
                // As the page's navigation hands the click over: a URL, which WebKit escapes as Foundation does.
                let href = Self.unescape(String(m.1))
                NoteLinks.open(URL(string: href)?.absoluteString ?? href, base: nil, openNote: { _ in }, openLink: opener)
                return Shown(name: Self.unescape(String(m.2)), opened: opened)
            case .editor:
                editor.load(written.text)
                _ = editor.openLink(at: written.at, event: click)
                return Shown(opened: opened)
            case .textEditor:
                text.string = written.text
                _ = text.openLink(at: written.address ?? written.at)
                return Shown(opened: opened)
            case .texPDF:
                preconditionFailure("Built once for every link: `texPDF(_:)`")
            }
        }

        /// The links `sources` (each a `\href`) put in the PDF they build with Tectonic, as the app builds, each as a click
        /// on it opens.
        func texPDF(_ sources: [String]) throws -> [AppLink?] {
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            // folio:not-an-action a test's temporary folder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var urls: [URL] = []
            let tex = folder.appending(path: "links.tex")
            let body = sources.map { "\\noindent \($0)\\par" }.joined(separator: "\n")
            try "\\documentclass{article}\n\\usepackage{hyperref}\n\\begin{document}\n\(body)\n\\end{document}\n".write(to: tex, atomically: true, encoding: .utf8)
            let build = try TexEngine.shared.compile(tex, into: folder, at: .now, calendar: .current)
            let pdf = try #require(build.pdf.flatMap(PDFDocument.init(url:)), "\(build.issues)")
            for i in 0..<pdf.pageCount {
                let links = (pdf.page(at: i)?.annotations ?? []).filter { $0.type == "Link" }.sorted { $0.bounds.maxY > $1.bounds.maxY }
                urls += links.compactMap { $0.url ?? ($0.action as? PDFActionURL)?.url }
            }
            try #require(urls.count == sources.count, "\(urls)")
            let view = PDFView()
            PDFLinks.attach(to: view, opener: opener)
            let links = try #require(view.delegate as? PDFLinks)
            return urls.map { url in
                opened = nil
                links.pdfViewWillClick(onLink: view, with: url)
                return opened
            }
        }

        static func unescape(_ s: String) -> String {
            s.replacing("&lt;", with: "<").replacing("&gt;", with: ">").replacing("&quot;", with: "\"").replacing("&#39;", with: "'")
                .replacing("&amp;", with: "&")
        }
    }

    /// The name the preview shows for a link without one of its own: what the app calls it, with its page, heading
    /// or moment. A note's link shows its title and heading, as before #347; its block shows on the card.
    static func expectedName(_ link: AppLink, written form: Form, named: Bool, in workspace: Workspace) -> String? {
        switch form {
        case .objectWiki, .addressWiki:
            if named { return alias }
            if link.kind == .note {
                let title = workspace.name(of: link)
                if case .heading(let h) = link.anchor { return title.map { "\($0) › \(h)" } }
                return title
            }
            return workspace.label(of: link)
        case .bare: return link.string
        case .markdown, .texHref: return alias
        case .textFile: return nil
        }
    }

    // MARK: The matrix

    @Test func everyFormIsSomewhereAndEverySurfaceHasAForm() {
        for form in Form.allCases {
            #expect(Surface.allCases.contains { Self.cell(form, $0) == .covered }, "\(form) opens nowhere")
        }
        for surface in Surface.allCases {
            #expect(Form.allCases.contains { Self.cell($0, surface) == .covered }, "\(surface) opens no form")
        }
    }

    @Test func everyKindOpensFromEveryFormAndSurface() throws {
        let workspace = try fixtureWorkspace()
        let samples = try Self.samples(workspace)
        // Every kind is sampled, and a page and settings tab each.
        #expect(Set(samples.map(\.link.kind)) == Set(AppLink.Kind.allCases))
        let views = try Views(workspace)
        var broken: [String] = []
        var unwritable: Set<String> = []
        for form in Form.allCases {
            for surface in Surface.allCases {
                guard Self.cell(form, surface) == .covered else { continue }
                for named in [false, true] where named || form == .objectWiki || form == .addressWiki {
                    var pdfSources: [(Sample, String)] = []
                    for sample in samples {
                        let written: Written
                        switch Self.write(sample.link, form, named: named) {
                        case .success(let w): written = w
                        case .failure(let why):
                            unwritable.insert("\(form) \(sample.link.kind): \(why.reason)")
                            continue
                        }
                        if surface == .texPDF {
                            pdfSources.append((sample, written.text))
                            continue
                        }
                        let shown = views.show(written, on: surface)
                        let cell = "\(form) × \(surface)\(named ? " named" : ""): \(sample.link.string)"
                        check(shown.opened, sample, cell, workspace, &broken)
                        if Self.showsName(surface) {
                            let want = Self.expectedName(sample.link, written: form, named: named, in: workspace)
                            if shown.name != want || want == nil { broken.append("\(cell) shows \(shown.name ?? "nothing"), not \(want ?? "nothing")") }
                        }
                    }
                    if surface == .texPDF {
                        let opened = try views.texPDF(pdfSources.map(\.1))
                        for ((sample, _), link) in zip(pdfSources, opened) {
                            check(link, sample, "\(form) × \(surface): \(sample.link.string)", workspace, &broken)
                        }
                    }
                }
            }
        }
        #expect(broken.isEmpty, "\(broken.joined(separator: "\n"))")
        // Only the kind-and-ID form has links it can't hold (places, course pages and settings tabs), and it says why.
        #expect(!unwritable.isEmpty && unwritable.allSatisfy { $0.hasPrefix("\(Form.objectWiki) ") }, "\(unwritable)")
    }

    func check(_ opened: AppLink?, _ sample: Sample, _ cell: String, _ workspace: Workspace, _ broken: inout [String]) {
        guard let opened else { return broken.append("\(cell) opens nothing") }
        guard opened == sample.link else { return broken.append("\(cell) opens \(opened.string)") }
        guard let entry = workspace.entry(for: opened) else { return broken.append("\(cell) finds nothing") }
        let screen = Screen(entry)
        if screen != sample.screen { broken.append("\(cell) draws \(screen), not \(sample.screen)") }
    }
}
