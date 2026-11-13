import FolioDomain
import FolioStorage
import SwiftUI

enum ItemSheet: Identifiable {
    case session(SessionSheetRequest)
    case exam(course: UUID, exam: UUID)
    case assignment(course: UUID, assignment: UUID)
    case review(course: UUID, unit: UUID)
    case card(course: UUID, draft: CardDraft)
    case generateCards(course: UUID, unit: UUID)
    case note(NoteSheetRequest)
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

struct NoteSheetRequest {
    let id = UUID()
    let course: UUID
    let note: NoteFile
    var moves: MoveUndo?
}

struct MaterialSheetRequest {
    let course: UUID
    let material: UUID
    var moves: MoveUndo?
}

struct MaterialSheet: View {
    @State private var model: MaterialsModel
    let material: UUID

    init(workspace: Workspace, course: LoadedCourse, request: MaterialSheetRequest) {
        _model = State(initialValue: MaterialsModel(workspace: workspace, course: course, moves: request.moves ?? MoveUndo()))
        material = request.material
    }

    var body: some View { MaterialLinksEditor(model: model, materialId: material) }
}

struct FileIntake: Identifiable, Equatable {
    let id = UUID()
    let course: UUID
    let folder: String
}

struct ItemSheetsAction {
    var present: @MainActor (ItemSheet) -> Void = { _ in }
    var confirm: @MainActor (PendingAction?) -> Void = { _ in }
    var addFiles: @MainActor (FileIntake) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var itemSheets = ItemSheetsAction()
}

// 모든 창이 녹음기의 요청을 지켜보고, 처음 받은 창이 요청을 지운다. 그래야 두 창이 함께 묻지 않는다.
struct ItemSheets: ViewModifier {
    let workspace: Workspace
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
            // 창 위에 놓이는 것(검색 팔레트)은 창이 값을 설정하는 곳 밖에 있으므로 다시 넘긴다.
            .environment(\.openLink, openLink)
            .onChange(of: workspace.wrapUpAsk) { _, ask in
                guard let ask, workspace.wrapUpAsk == ask else { return }
                let request = SessionSheetRequest(course: ask.course, session: ask.session, viewed: ask.viewed, recorded: true, asked: true)
                #if os(macOS)
                guard active else { return }
                workspace.wrapUpAsk = nil
                shown = .session(request)
                #else
                workspace.wrapUpAsk = nil
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
