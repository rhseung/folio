import FolioDomain
import FolioStorage
import SwiftUI

/// A sheet an item menu opens. Shown by the window rather than the row that asked, so every place that shows an item
/// (Today, the ribbon, search) can edit and delete it, not only the item's own screen.
enum ItemSheet: Identifiable {
    case session(SessionSheetRequest)
    case exam(course: UUID, exam: UUID)
    case assignment(course: UUID, assignment: UUID)
    case review(course: UUID, unit: UUID)
    /// A card to edit, or a new one in a unit.
    case card(course: UUID, draft: CardDraft)
    /// Cards made by Claude for a unit.
    case generateCards(course: UUID, unit: UUID)
    case note(NoteSheetRequest)
    /// 옮기기 ▸ 새 폴더….
    case noteFolder(NoteSheetRequest)
    case material(MaterialSheetRequest)
    case course(UUID)

    var id: UUID {
        switch self {
        case .session(let request): request.id
        case .exam(_, let id), .assignment(_, let id), .review(_, let id), .generateCards(_, let id): id
        case .card(_, let draft): draft.id
        case .note(let request), .noteFolder(let request): request.id
        case .material(let request): request.material
        case .course(let id): id
        }
    }
}

/// A note by its file: one moved in from an old folder has no ID until it is opened. `moves` is the notes section's
/// undo, which a rename from its list or its open note lands in.
struct NoteSheetRequest {
    let id = UUID()
    let course: UUID
    let note: NoteFile
    var moves: MoveUndo?
}

struct MaterialSheetRequest {
    let course: UUID
    let material: UUID
    /// The materials page's undo, which a rename from it lands in.
    var moves: MoveUndo?
}

/// The file's sheet, with a materials model of its own, since the window shows it from anywhere.
struct MaterialSheet: View {
    @State private var model: MaterialsModel
    let material: UUID

    init(workspace: Workspace, course: LoadedCourse, request: MaterialSheetRequest) {
        _model = State(initialValue: MaterialsModel(workspace: workspace, course: course, moves: request.moves ?? MoveUndo()))
        material = request.material
    }

    var body: some View { MaterialLinksEditor(model: model, materialId: material) }
}

/// Files picked to go into a course folder, as dropping them there does.
struct FileIntake: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    /// Course-relative.
    let folder: String
}

/// What an item menu asks of its window: a sheet, a confirmation (`Workspace.ask`), or files to add.
struct ItemSheetsAction {
    var present: @MainActor (ItemSheet) -> Void = { _ in }
    var confirm: @MainActor (PendingAction?) -> Void = { _ in }
    var addFiles: @MainActor (FileIntake) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var itemSheets = ItemSheetsAction()
}

/// Shows, per window, the sheets and confirmations item menus ask for, and the class sheet a stopped recording asks
/// for. Every window watches the recorder's ask; the first that takes it clears it, so two windows don't both ask.
struct ItemSheets: ViewModifier {
    let workspace: Workspace
    /// Set inside this modifier's content, so the sheet, attached outside it, is given it again.
    let openLink: OpenLinkAction
    @State private var shown: ItemSheet?
    @State private var pending: PendingAction?
    @State private var intake: FileIntake?
    #if os(macOS)
    @Environment(\.appearsActive) private var active
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.itemSheets, ItemSheetsAction(present: { shown = $0 }, confirm: { pending = $0 }, addFiles: { intake = $0 }))
            // Again for what is laid over the window (the search palette), which sits outside where the window sets it.
            .environment(\.openLink, openLink)
            .onChange(of: workspace.wrapUpAsk) { _, ask in
                guard let ask, workspace.wrapUpAsk == ask else { return }
                let request = SessionSheetRequest(course: ask.course, session: ask.session, viewed: ask.viewed, recorded: true, asked: true)
                #if os(macOS)
                // The stop button was in the key window.
                guard active else { return }
                workspace.wrapUpAsk = nil
                shown = .session(request)
                #else
                workspace.wrapUpAsk = nil
                // The recording card's popover is still going away; a sheet asked for meanwhile is dropped.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    shown = .session(request)
                }
                #endif
            }
            .sheet(item: $shown) { sheet in
                switch sheet {
                case .session(let request): SessionSheet(workspace: workspace, request: request).environment(\.openLink, openLink)
                case .exam(let course, let id):
                    if let course = workspace.course(course), let exam = course.file.exams.first(where: { $0.id == id }) {
                        ExamEditor(workspace: workspace, course: course, exam: exam)
                    }
                case .assignment(let course, let id):
                    if let loaded = workspace.course(course), let assignment = loaded.file.assignments.first(where: { $0.id == id }) {
                        AssignmentSheet(workspace: workspace, course: loaded, assignment: assignment) { material, placement in
                            openLink(AppLink(.material, material), in: placement, course: course)
                        }
                        .environment(\.openLink, openLink)
                    }
                case .review(let course, let unit):
                    ReviewView(workspace: workspace, courseId: course, unitId: unit)
                case .card(let course, let draft):
                    if let course = workspace.course(course) {
                        CardEditorSheet(workspace: workspace, course: course, draft: draft, units: course.file.units) {}
                    }
                case .generateCards(let course, let unit):
                    if let course = workspace.course(course), let unit = course.file.units.first(where: { $0.id == unit }) {
                        GenerateCardsSheet(workspace: workspace, course: course, unit: unit) {}
                    }
                case .note(let request):
                    if let course = workspace.course(request.course) {
                        NoteEditSheet(workspace: workspace, course: course, note: request.note, moves: request.moves)
                    }
                case .noteFolder(let request):
                    if let course = workspace.course(request.course) {
                        NoteFolderSheet(workspace: workspace, course: course, note: request.note, moves: request.moves)
                    }
                case .course(let id):
                    if let course = workspace.course(id) { EditCourseSheet(workspace: workspace, course: course) }
                case .material(let request):
                    if let course = workspace.course(request.course) {
                        MaterialSheet(workspace: workspace, course: course, request: request).environment(\.openLink, openLink)
                    }
                }
            }
            .confirming($pending)
            .fileImporter(
                isPresented: Binding(get: { intake != nil }, set: { if !$0 { intake = nil } }),
                allowedContentTypes: [.item], allowsMultipleSelection: true
            ) { [intake] result in
                if case .success(let urls) = result, let intake { workspace.importFiles(urls, into: intake.folder, course: intake.course) }
            }
    }
}

extension View {
    func itemSheets(_ workspace: Workspace, openLink: OpenLinkAction) -> some View {
        modifier(ItemSheets(workspace: workspace, openLink: openLink))
    }
}
