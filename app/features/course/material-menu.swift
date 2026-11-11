import Algorithms
import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

/// A file's menu, the same in the materials list, on its page's `⋯`, an exam's or a unit's files and search (#403).
@MainActor
struct MaterialMenuSource: ItemMenuSource {
    let workspace: Workspace
    let courseId: UUID
    let material: FolioDomain.Material
    let host: MenuHost
    /// The materials page's undo, which the menu's moves land in.
    var moves: MoveUndo?
    /// The materials page's file picker for a missing file; elsewhere the row opens that page, where the file is shown missing.
    var relink: (@MainActor () -> Void)?
    /// The materials page asks with the file's path; elsewhere `material untrack` asks as it declares.
    var untrack: (@MainActor () -> Void)?
    let openLink: OpenLinkAction
    let sheets: ItemSheetsAction

    private var course: LoadedCourse? { workspace.course(courseId) }
    private var url: URL? { course?.store.fileURL(material.path) }
    private var pdf: FolioDomain.Material? { course?.file.materials.builtPDF(of: material) }

    var commands: [MaterialCommand] {
        #if os(macOS)
        let mac = true
        #else
        let mac = false
        #endif
        return course?.file.commands(for: material, host: host, pdf: pdf.map(\.id), mac: mac) ?? []
    }

    func row(_ command: MaterialCommand) -> MenuRow {
        switch command {
        case .open:
            MenuRow(command, material.isFolder ? .materialsOpenInFinder : .commonOpen, "arrow.right.circle", .action(open))
        case .openWithDefault:
            MenuRow(command, .materialsOpenWithDefault, "arrow.up.forward.app", .action { if let url { openWithDefault(url) } })
        case .openInEditor:
            MenuRow(command, .fileViewOpenInEditor, "chevron.left.forwardslash.chevron.right", .submenu(editorLeaves))
        case .openPDF(let id):
            MenuRow(command, .materialsOpenPdf, "doc.richtext", .action { openLink(AppLink(.material, id), course: courseId) })
        case .edit:
            .edit(command) { sheets.present(.material(MaterialSheetRequest(course: courseId, material: material.id, moves: moves))) }
        case .move:
            MenuRow(command, .materialsMoveTo, "folder", .submenu(moveLeaves))
        case .unlink(let host):
            MenuRow(command, unlinkTitle(host), "link.badge.minus", .action { unlink(from: host) })
        case .share:
            .share(command, AppLink(.material, material.id), course: courseId)
        case .showInFinder:
            MenuRow(command, .commonShowInFinder, "folder", .action { if let url { revealInFinder(url) } })
        case .remove:
            MenuRow(command, .materialsTrashEllipsis, "trash", role: .destructive, .action {
                sheets.confirm(workspace.ask(MaterialTrash(course: courseId, material: material.id), button: .materialsTrash))
            })
        case .relink:
            MenuRow(command, .materialsRelinkEllipsis, "doc.badge.arrow.up", .action {
                if let relink { relink() } else { openLink(.course(courseId, page: .materials), course: courseId) }
            })
        case .untrack:
            MenuRow(command, .materialsUntrackEllipsis, "minus.circle", role: .destructive, .action {
                if let untrack { untrack() } else { sheets.confirm(workspace.ask(MaterialUntrack(course: courseId, material: material.id))) }
            })
        }
    }

    private func open() {
        #if os(macOS)
        if material.isFolder, let url { return openWithDefault(url) }
        #endif
        openLink(AppLink(.material, material.id), course: courseId)
    }

    private func openWithDefault(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private var editorLeaves: [MenuRow.Leaf] {
        #if os(macOS)
        guard let url else { return [] }
        return EditorMenu.installed.map { editor in
            MenuRow.Leaf(id: editor.app, title: editor.name, symbol: "app") {
                NSWorkspace.shared.open([url], withApplicationAt: editor.app, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        #else
        return []
        #endif
    }

    /// The standard places of the course folder it may go, each exam's folder among them. Read when the menu is drawn.
    private var moveLeaves: [MenuRow.Leaf] {
        guard let course else { return [] }
        let folders = (try? course.store.assignmentFolders()) ?? []
        let exams = course.file.exams.compactMap { MaterialIntake.folder(of: $0) }
        let here = (material.path as NSString).deletingLastPathComponent
        let places = Array(([CourseFolder.lectures.rawValue] + MaterialIntake.places(assignmentFolders: folders) + exams).uniqued()).filter { $0 != here }
        return places.map { place in
            MenuRow.Leaf(id: place, title: place, symbol: "folder") {
                let action = MaterialMove(course: courseId, material: material.id, to: "\(place)/\((material.path as NSString).lastPathComponent)")
                sheets.confirm(workspace.ask(action) { [moves] ctx in moves?.keep(ctx) })
            }
        }
    }

    private func unlinkTitle(_ host: MenuHost) -> LocalizedStringResource {
        if case .unit = host { return .unitsUnlinkMaterial }
        return .examsUnlinkMaterial
    }

    private func unlink(from host: MenuHost) {
        switch host {
        case .exam(let exam): workspace.run(MaterialLinkExam(course: courseId, material: material.id, exam: exam, linked: false))
        case .unit(let unit): workspace.run(MaterialLinkUnit(course: courseId, material: material.id, unit: unit, linked: false))
        case .own, .elsewhere, .list: break
        }
    }
}

/// For `.contextMenu` and a file's `⋯`.
struct MaterialMenu: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.openLink) private var openLink
    @Environment(\.itemSheets) private var sheets
    let courseId: UUID
    let materialId: UUID
    var host: MenuHost = .elsewhere
    var moves: MoveUndo?
    var relink: (@MainActor () -> Void)?
    var untrack: (@MainActor () -> Void)?

    var body: some View {
        if let material = workspace.course(courseId)?.file.materials.first(where: { $0.id == materialId }) {
            ItemMenu(source: MaterialMenuSource(workspace: workspace, courseId: courseId, material: material, host: host, moves: moves,
                                                relink: relink, untrack: untrack, openLink: openLink, sheets: sheets))
        }
    }
}
