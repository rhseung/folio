#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import PDFKit
import SwiftUI

/// Debug-only: draws every editing sheet on its own into `form-<name>.png`, so the forms can be compared side by side.
/// The offscreen renders in app-tests draw the same list.
enum FormSnapshots {
    @MainActor static func forms(_ workspace: Workspace) -> [(String, AnyView)] {
        guard let course = workspace.currentCourses.first(where: { !$0.file.exams.isEmpty }) ?? workspace.currentCourses.first,
              let semester = workspace.currentSemester else { return [] }
        let file = course.file
        let device = workspace.device
        let component = file.components.first ?? GradeComponent(device: device, at: .now, name: "과제", weight: 20)
        let importPlaces = MaterialIntake.places(assignmentFolders: ["HW01", "HW02", "SP01"]) + ["Exams/Midterm", "Exams/Final"]
        var forms: [(String, AnyView)] = [
            ("semester-add", AnyView(AddSemesterSheet(workspace: workspace) { _ in })),
            ("course-add", AnyView(AddCourseSheet(workspace: workspace, semester: semester) { _ in })),
            ("course-edit", AnyView(EditCourseSheet(workspace: workspace, course: course))),
            ("course-icon", AnyView(CourseIconPanel(icon: nil, color: workspace.accent(course.id).color) { _ in })),
            ("class-times", AnyView(ClassTimesSheet(workspace: workspace, course: course))),
            ("session-add", AnyView(SessionFormSheet(workspace: workspace, course: course))),
            ("note-new", AnyView(NewNoteSheet(workspace: workspace, course: course, kind: .review) { _ in })),
            ("note-new-topic", AnyView(NewNoteSheet(workspace: workspace, course: course, kind: .topic) { _ in })),
            ("exam-new", AnyView(ExamEditor(workspace: workspace, course: course, exam: Exam(device: device, at: .now, title: "")))),
            ("assignment", AnyView(AssignmentSheet(workspace: workspace, course: course, assignment: file.assignments.first ?? Assignment(device: device, at: .now, title: "")) { _, _ in })),
            ("component", AnyView(ComponentSheet(workspace: workspace, course: course, component: component))),
            ("score", AnyView(ScoreEntrySheet(workspace: workspace, course: course, entry: file.scores.first ?? ScoreEntry(device: device, at: .now, componentId: component.id, title: "", score: 0, max: 10)))),
            ("policy", AnyView(PolicySheet(workspace: workspace, course: course))),
            ("requirement", AnyView(RequirementSheet(workspace: workspace, category: workspace.requirementCatalog.categories.first ?? RequirementCategory(device: device, at: .now, name: "")))),
            ("profile", AnyView(ProfileSheet(workspace: workspace))),
            ("import-place", AnyView(ImportPlaceSheet(workspace: workspace, course: course, files: [URL(filePath: "/tmp/Flows.pdf")],
                                                      places: importPlaces))),
            ("import-place-many", AnyView(ImportPlaceSheet(workspace: workspace, course: course,
                                                           files: ["10_Matchings.pdf", "Lecture 9 - Paths.pdf", "Flows.pdf", "HW2.pdf", "Diestel GT 5th edition.pdf",
                                                                   "2024 중간고사 기출.pdf"].map { URL(filePath: "/tmp/\($0)") },
                                                           places: importPlaces))),
            ("material-new", AnyView(NewMaterialFileSheet(workspace: workspace, course: course, folder: nil) { _ in })),
        ]
        let users = workspace.allCourses.flatMap(\.codes)
        if let code = workspace.catalog.codes.max(by: { a, b in users.filter { $0 == a.id }.count < users.filter { $0 == b.id }.count }) {
            let courses = workspace.allCourses.filter { $0.codes.contains(code.id) }.map(\.id)
            forms.append(("code", AnyView(CodeEditor(model: CodesModel(workspace: workspace), code: .constant(code), programs: [code.program], courses: courses) {})))
        }
        if let session = file.sessions.first { forms.append(("session-edit", AnyView(SessionFormSheet(workspace: workspace, course: course, session: session)))) }
        if let exam = file.exams.first { forms.append(("exam-edit", AnyView(ExamEditor(workspace: workspace, course: course, exam: exam)))) }
        if let note = try? course.store.notes().first {
            forms.append(("note-rename", AnyView(NoteRenameSheet(workspace: workspace, course: course, note: note))))
            forms.append(("note-folder", AnyView(NoteFolderSheet(workspace: workspace, course: course, note: note))))
        }
        if let unit = file.units.first { forms.append(("card", AnyView(CardEditorSheet(workspace: workspace, course: course, draft: CardDraft(unitId: unit.id), units: file.units) {}))) }
        forms += lectureSections(workspace, places: importPlaces)
        return forms
    }

    /// A course whose slides its units split (#321): the add sheet proposing the next deck's units, the split screen
    /// on a drawn deck, and the progress sheet's bar over the zones.
    @MainActor static func lectureSections(_ workspace: Workspace, places: [String]) -> [(String, AnyView)] {
        guard let course = workspace.currentCourses.first(where: { c in c.file.lectureFiles.contains { c.file.isSplit($0.id) } }),
              let slides = course.file.lectureFiles.first(where: { course.file.isSplit($0.id) }) else { return [] }
        let file = course.file
        let accent = workspace.accent(course.id)
        var forms: [(String, AnyView)] = []

        let model = ImportPlaceModel(workspace: workspace, course: course, files: [URL(filePath: "/tmp/06_Matchings in general graphs.pdf")],
                                     places: places) { _, _, _ in .unreadable }
        if var proposal = LectureSplit([.init(title: "Matchings", firstPage: 1, lastPage: 1), .init(title: "Hall's theorem", firstPage: 7, lastPage: 7),
                                        .init(title: "Tutte's theorem", firstPage: 15, lastPage: 15), .init(title: "", firstPage: 23, lastPage: 23)],
                                       pageCount: 26) {
            proposal = SectionMatch.match(proposal, units: file.units)
            for (i, title) in ["매칭", "Hall의 정리"].enumerated() {
                proposal.setUnit(file.units.first { $0.title == title }?.id, of: i, match: .claude)
            }
            proposal.setUnit(nil, of: 3)
            model.show(.proposed(proposal, source: .claude), for: 0)
            forms.append(("import-place-sections", AnyView(ImportPlaceSheet(model: model).environment(\.accent, accent))))
        }
        if let document = SampleLecture.document() {
            let split = LectureSplit(file: file, material: slides.id, pageCount: document.pageCount)
            forms.append(("lecture-split", AnyView(LectureSplitPane(controller: PDFController(document: document, page: 8), split: .constant(split),
                                                                     units: file.units, note: String(localized: .fileViewSplitFound), save: {}, cancel: {})
                    .frame(width: 1180, height: 720).background(Theme.Palette.card).environment(\.accent, accent))))
        }
        if let session = file.sessions.first(where: { file.splitProgress(of: $0) != nil }) {
            forms.append(("class-wrap-up", AnyView(ClassWrapUpSheet(workspace: workspace, course: course.id, session: session.id))))
        }
        return forms
    }

    @MainActor static func capture(_ workspace: Workspace, into directory: URL) async {
        for (name, view) in forms(workspace) {
            let host = NSHostingView(rootView: view.environment(workspace))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            try? await Task.sleep(for: .seconds(0.8))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                // folio:not-an-action debug screenshots, outside the GIST folder
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "form-\(name).png"))
            }
            window.orderOut(nil)
        }
    }
}
#endif
