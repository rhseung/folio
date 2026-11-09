#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import FolioFixtures
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
            ("session-add", AnyView(SessionSheet(workspace: workspace, request: SessionSheetRequest(course: course.id)))),
            ("note-new", AnyView(NewNoteSheet(workspace: workspace, course: course, kind: .review) { _ in })),
            ("note-new-unit", AnyView(NewNoteSheet(workspace: workspace, course: course, kind: .unit) { _ in })),
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
        // The memo grows with its text: empty, one line, a long unbroken URL among a few lines, and past the cap.
        let assignment = file.assignments.first ?? Assignment(device: device, at: .now, title: "HW01")
        let url = "https://lms.example.ac.kr/course/view.php?id=104729&section=assignment-submission-guidelines-and-rubric-2026-fall"
        let steps = { (n: Int) in (1...n).map { "\($0). 문제 \($0)의 풀이 과정을 빠짐없이 적는다" }.joined(separator: "\n") }
        for (name, memo) in [("empty", ""), ("short", "채점 기준은 LMS 공지 참고"),
                             ("long", "제출 안내\n\(url)\n\(steps(4))"), ("overflow", "제출 안내\n\(url)\n\(steps(14))")] {
            var a = assignment
            a.memo = memo
            forms.append(("assignment-memo-\(name)", AnyView(AssignmentSheet(workspace: workspace, course: course, assignment: a) { _, _ in })))
        }
        let users = workspace.allCourses.flatMap(\.codes)
        if let code = workspace.catalog.codes.max(by: { a, b in users.filter { $0 == a.id }.count < users.filter { $0 == b.id }.count }) {
            let courses = workspace.allCourses.filter { $0.codes.contains(code.id) }.map(\.id)
            forms.append(("code", AnyView(CodeEditor(model: CodesModel(workspace: workspace), code: .constant(code), programs: [code.program], courses: courses) {})))
        }
        if let session = file.sessions.first { forms.append(("session-edit", AnyView(SessionSheet(workspace: workspace, request: SessionSheetRequest(course: course.id, session: session.id))))) }
        if let exam = file.exams.first { forms.append(("exam-edit", AnyView(ExamEditor(workspace: workspace, course: course, exam: exam)))) }
        if let note = try? course.store.notes().first {
            forms.append(("note-rename", AnyView(NoteRenameSheet(workspace: workspace, course: course, note: note))))
            forms.append(("note-folder", AnyView(NoteFolderSheet(workspace: workspace, course: course, note: note))))
        }
        if let unit = file.units.first { forms.append(("card", AnyView(CardEditorSheet(workspace: workspace, course: course, draft: CardDraft(unitId: unit.id), units: file.units) {}))) }
        forms += lectureSections(workspace, places: importPlaces)
        forms += wrapUps(workspace)
        forms += sessionMenus(workspace)
        return forms
    }

    /// A class's menu after it and ahead of it, on its own page, drawn from the rows the menu shows (`MenuPicture`).
    @MainActor static func sessionMenus(_ workspace: Workspace) -> [(String, AnyView)] {
        let now = workspace.now
        var forms: [(String, AnyView)] = []
        for course in workspace.currentCourses {
            let file = course.file
            let over = file.sessions.filter { !$0.isCancelled && $0.date < now }
            let past = over.max { file.recordings(of: $0).count < file.recordings(of: $1).count }
            let ahead = file.sessions.first { !$0.isCancelled && $0.date > now }
            for (name, session) in [("menu-session-after", past), ("menu-session-ahead", ahead)] where !forms.contains(where: { $0.0 == name }) {
                guard let session else { continue }
                let source = SessionMenuSource(workspace: workspace, courseId: course.id, session: session, host: .own, now: now, openNote: { _ in },
                                               openLink: OpenLinkAction(), openURL: OpenURLAction { _ in .handled }, sheets: ItemSheetsAction())
                forms.append((name, AnyView(MenuPicture(rows: source.commands.map(source.row)))))
            }
            // Ahead of a class the sheet leads with its time; picked as 휴강, it has nothing else.
            if let ahead, !forms.contains(where: { $0.0 == "session-ahead" }) {
                forms.append(("session-ahead", AnyView(SessionSheet(workspace: workspace, request: SessionSheetRequest(course: course.id, session: ahead.id)))))
                let cancelled = SessionSheetModel(workspace: workspace, course: course.id, session: ahead.id)
                cancelled.setKind(.cancelled)
                forms.append(("session-cancelled", AnyView(SessionSheet(model: cancelled))))
            }
        }
        return forms
    }

    /// A class's sheet as a stopped recording or Today's card asks for it.
    @MainActor static func wrapUp(_ workspace: Workspace, _ course: UUID, _ session: UUID) -> SessionSheet {
        SessionSheet(workspace: workspace, request: SessionSheetRequest(course: course, session: session, asked: true))
    }

    /// The wrap-up of a class with nothing yet and of the class with the most, in a course with lecture files.
    @MainActor static func wrapUps(_ workspace: Workspace) -> [(String, AnyView)] {
        guard let course = workspace.currentCourses.first(where: { !$0.file.lectureFiles.isEmpty }) else { return [] }
        let file = course.file
        let held = file.sessions.filter { !$0.isCancelled }.map { (session: $0, gaps: file.wrapUpGaps(of: $0).count) }
        var forms: [(String, AnyView)] = []
        if let empty = held.last(where: { $0.gaps == WrapUpItem.allCases.count }) {
            forms.append(("class-wrap-up-empty", AnyView(wrapUp(workspace, course.id, empty.session.id))))
        }
        // The toolbar's quick-add mid-typing, as its popover lays it out: the deadline's pill and what will be saved.
        forms.append(("quick-add-typing", AnyView(QuickAddField(workspace: workspace, showsEmptyChips: true, floating: true).padding(Theme.Space.l).frame(width: 440)
            .environment(\.quickAddTypedSample, "\(file.course.title.split(separator: " ").first ?? "") Lab3 보고서 금 마감"))))
        if let filled = held.min(by: { $0.gaps < $1.gaps }), filled.gaps < WrapUpItem.allCases.count {
            forms.append(("class-wrap-up-filled", AnyView(wrapUp(workspace, course.id, filled.session.id))))
            forms.append(("class-wrap-up-dragging", AnyView(wrapUp(workspace, course.id, filled.session.id)
                .environment(\.pageRangeNumbersShown, true))))
        }
        // The same bar, compact, in the popover that links a split lecture file to its classes.
        if let lecture = file.lectureFiles.first(where: { !PageRangeField.Section.list(file, material: $0.id, pageCount: nil).isEmpty }) {
            forms.append(("material-links", AnyView(MaterialLinksEditor(model: MaterialsModel(workspace: workspace, course: course), materialId: lecture.id)
                .courseAccent(workspace.accent(course.id)))))
        }
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
            forms.append(("import-place-sections", AnyView(ImportPlaceSheet(model: model).courseAccent(accent))))
        }
        if let document = PDFDocument(data: SampleLecture.data()) {
            let split = LectureSplit(file: file, material: slides.id, pageCount: document.pageCount)
            forms.append(("lecture-split", AnyView(LectureSplitPane(controller: PDFController(document: document, page: 8), split: .constant(split),
                                                                     units: file.units, note: nil, save: {}, cancel: {})
                    .frame(width: 1180, height: 720).background(Theme.Palette.card).courseAccent(accent))))
        }
        if let session = file.sessions.first(where: { file.splitProgress(of: $0) != nil }) {
            forms.append(("class-wrap-up", AnyView(wrapUp(workspace, course.id, session.id))))
        }
        forms.append(("material-links", AnyView(MaterialLinksEditor(model: MaterialsModel(workspace: workspace, course: course), materialId: slides.id)
            .courseAccent(accent))))
        return forms
    }

    @MainActor static func capture(_ workspace: Workspace, into directory: URL) async {
        for (name, view) in forms(workspace) {
            let host = NSHostingView(rootView: view.environment(workspace).snapshotKey())
            // Sized here, once the sheet has loaded: left to the hosting view, a sheet whose text grows after it
            // appears (a memo loaded in onAppear) kept the window's first height and squeezed the text area.
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            try? await Task.sleep(for: .seconds(0.8))
            window.setContentSize(host.fittingSize)
            try? await Task.sleep(for: .seconds(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                // folio:not-an-action debug screenshots, outside the GIST folder
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "form-\(name).png"))
            }
            window.orderOut(nil)
        }
    }
}

/// Debug-only: an item menu's rows as a picture. The system draws a context menu in a window of its own, which neither
/// the offscreen renders nor the window snapshots capture, so this is how a render shows which rows stand and where
/// the dividers fall. The rows are the menu's own; only the frame is drawn here.
struct MenuPicture: View {
    let rows: [MenuRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                if i > 0 && rows[i - 1].group.band != row.group.band {
                    Theme.Palette.lineSoft.frame(height: 1).padding(.vertical, Theme.Space.xs).padding(.horizontal, Theme.Space.s)
                }
                line(row)
            }
        }
        .padding(.vertical, Theme.Space.xs)
        .frame(width: 280)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
        .padding(Theme.Space.xl)
        .background(Theme.Palette.page)
    }

    func line(_ row: MenuRow) -> some View {
        let checked: Bool, submenu: Bool
        switch row.kind {
        case .check(let on, _): (checked, submenu) = (on, false)
        case .submenu, .share: (checked, submenu) = (false, true)
        case .action: (checked, submenu) = (false, false)
        }
        return HStack(spacing: Theme.Space.s) {
            Image(systemName: "checkmark").font(Theme.Glyph.small).opacity(checked ? 1 : 0).frame(width: 12)
            Image(systemName: row.symbol).frame(width: 16)
            Text(row.title)
            Spacer(minLength: Theme.Space.xl)
            if submenu { Image(systemName: "chevron.right").font(Theme.Glyph.small) }
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(row.role == .destructive ? Theme.Palette.danger : row.disabled ? Theme.Palette.textTertiary : Theme.Palette.text)
        .padding(.horizontal, Theme.Space.m)
        .frame(height: 24)
    }
}

#endif
