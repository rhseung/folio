#if DEBUG && os(macOS)
import AppKit
import FolioDomain
import SwiftUI

/// Debug-only: draws every editing sheet on its own into `form-<name>.png`, so the forms can be compared side by side.
enum FormSnapshots {
    @MainActor static func capture(_ workspace: Workspace, into directory: URL) async {
        guard let course = workspace.currentCourses.first(where: { !$0.file.exams.isEmpty }) ?? workspace.currentCourses.first,
              let semester = workspace.currentSemester else { return }
        let file = course.file
        let device = workspace.device
        let component = file.components.first ?? GradeComponent(device: device, at: .now, name: "과제", weight: 20)
        var forms: [(String, AnyView)] = [
            ("semester-add", AnyView(AddSemesterSheet(workspace: workspace) { _ in })),
            ("course-add", AnyView(AddCourseSheet(workspace: workspace, semester: semester) { _ in })),
            ("course-edit", AnyView(EditCourseSheet(course: course))),
            ("course-icon", AnyView(CourseIconPanel(icon: nil, color: workspace.accent(course.id).color) { _ in })),
            ("class-times", AnyView(ClassTimesSheet(course: course))),
            ("session-add", AnyView(AddSessionSheet(course: course))),
            ("exam-new", AnyView(ExamEditor(course: course, exam: Exam(device: device, at: .now, kind: .midterm, title: "")))),
            ("assignment", AnyView(AssignmentSheet(course: course, assignment: file.assignments.first ?? Assignment(device: device, at: .now, title: "")))),
            ("component", AnyView(ComponentSheet(workspace: workspace, course: course, component: component))),
            ("score", AnyView(ScoreEntrySheet(workspace: workspace, course: course, entry: file.scores.first ?? ScoreEntry(device: device, at: .now, componentId: component.id, title: "", score: 0, max: 10)))),
            ("policy", AnyView(PolicySheet(workspace: workspace, course: course))),
            ("requirement", AnyView(RequirementSheet(workspace: workspace, category: workspace.requirementCatalog.categories.first ?? RequirementCategory(device: device, at: .now, name: "")))),
            ("profile", AnyView(ProfileSheet(workspace: workspace))),
            ("import-place", AnyView(ImportPlaceSheet(course: course, files: [URL(filePath: "/tmp/slides.pdf")],
                                                      places: MaterialIntake.places(assignmentFolders: ["HW01", "HW02", "SP01"]) + ["Exams/Midterm", "Exams/Final"]))),
        ]
        let users = workspace.allCourseRecords.flatMap(\.codes)
        if let code = workspace.catalog.codes.max(by: { a, b in users.filter { $0 == a.id }.count < users.filter { $0 == b.id }.count }) {
            let courses = workspace.allCourseRecords.filter { $0.codes.contains(code.id) }.map(\.id)
            forms.append(("code", AnyView(CodeEditor(model: CodesModel(workspace: workspace), code: .constant(code), programs: [code.program], courses: courses) {})))
        }
        if let exam = file.exams.first { forms.append(("exam-edit", AnyView(ExamEditor(course: course, exam: exam)))) }
        if let unit = file.units.first { forms.append(("card", AnyView(CardEditorSheet(workspace: workspace, course: course, draft: CardDraft(unitId: unit.id), units: file.units) {}))) }
        for (name, view) in forms {
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
