import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation

@MainActor @Observable final class AssetTrayModel {
    let editor: NoteEditorModel
    var filter = NoteAsset.Filter.all
    var search = ""
    var expanded = false
    var viewing: NoteAsset?
    var quickLook: URL?
    var picking = false
    private(set) var assets: [NoteAsset] = []
    @ObservationIgnored private var files: [String: URL] = [:]
    // 서랍이 열려 있는 동안 타자마다 본문을 다시 훑지 않도록, 마지막으로 훑은 본문의 결과를 둔다.
    @ObservationIgnored private var use: (body: String, use: NoteAssetUse)?

    init(editor: NoteEditorModel) { self.editor = editor }

    var workspace: Workspace { editor.workspace }
    var revision: [Int] { [editor.assetsRevision, workspace.notesRevision] }

    func reload() {
        let urls = editor.store.noteAssets()
        files = Dictionary(urls.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        let modified = { (url: URL) in (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        let widgets = (try? workspace.read(NoteWidgetList(course: editor.course.id))) ?? []
        assets =
            urls.map { NoteAsset.file($0.lastPathComponent, modified: modified($0)) }
            + widgets.compactMap { item in
                UUID(uuidString: item.name).map { NoteAsset.widget($0, title: item.title, modified: item.modified) }
            }
    }

    var shelf: NoteAssetShelf { NoteAssetShelf(assets, use: currentUse, filter: filter, search: expanded ? search : "") }
    var isEmpty: Bool { assets.isEmpty }

    private var currentUse: NoteAssetUse {
        let body = editor.body
        if let use, use.body == body { return use.use }
        let made = NoteAssetUse(body)
        use = (body, made)
        return made
    }

    func used(_ asset: NoteAsset) -> Bool { currentUse.contains(asset) }

    // MARK: Inserting

    // 시트의 큰 높이에서 넣으면 본문이 가려지므로, 넣은 자리를 보이게 낮은 높이로 내린다.
    func insert(_ asset: NoteAsset, collapsing: Bool = false) {
        switch asset.ref {
        case .file(let name):
            guard let url = files[name] else { return }
            editor.pendingInsert = editor.assetLink(url)
        case .widget(let id):
            editor.pendingBlock = CBWidget.block(id)
        }
        if collapsing { expanded = false }
    }

    // 끌어 놓는 자리는 줄 가운데일 수 있으므로 위젯 블록은 앞뒤에 줄을 바꿔 제 줄에 놓는다.
    func dragText(_ asset: NoteAsset) -> String {
        switch asset.ref {
        case .file(let name): files[name].map(editor.assetLink) ?? name
        case .widget(let id): "\n" + CBWidget.block(id) + "\n"
        }
    }

    func addFiles(_ urls: [URL]) { editor.addAssets(urls) }

    // MARK: Showing

    func fileURL(_ asset: NoteAsset) -> URL? {
        switch asset.ref {
        case .file(let name): files[name]
        case .widget(let id): editor.store.fileURL(NoteWidget.path(id))
        }
    }

    func thumbnail(_ asset: NoteAsset, dark: Bool, accent: CourseAccent) -> AssetThumbnails.Request? {
        guard let url = fileURL(asset) else { return nil }
        let source: AssetThumbnails.Source
        switch (asset.kind, asset.ref) {
        case (.figure, _): source = .figure(url)
        case (.widget, .widget(let id)): source = .widget(id, file: url)
        default: return nil
        }
        return AssetThumbnails.Request(source: source, modified: asset.modified, noteFolder: editor.baseURL, dark: dark, accent: accent)
    }

    func name(_ asset: NoteAsset) -> String { asset.name.isEmpty ? String(localized: .notesAssetsKindWidget) : asset.name }

    func kindLabel(_ kind: NoteAsset.Kind) -> String {
        switch kind {
        case .figure: String(localized: .notesAssetsKindFigure)
        case .widget: String(localized: .notesAssetsKindWidget)
        case .image: String(localized: .notesAssetsKindImage)
        case .file: String(localized: .notesAssetsKindFile)
        }
    }

    func detail(_ asset: NoteAsset) -> String {
        let place = String(localized: used(asset) ? .notesAssetsInNote : .notesAssetsNotYet)
        return String(localized: .notesAssetsDetail(kindLabel(asset.kind), place))
    }

    static func symbol(_ kind: NoteAsset.Kind) -> String {
        switch kind {
        case .figure: "scribble.variable"
        case .widget: "slider.horizontal.3"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var filters: [(NoteAsset.Filter, String)] {
        NoteAsset.Filter.allCases.map { filter in
            let label: String =
                switch filter {
                case .all: String(localized: .notesAssetsFilterAll)
                case .figures: String(localized: .notesAssetsFilterFigures)
                case .widgets: String(localized: .notesAssetsFilterWidgets)
                case .files: String(localized: .notesAssetsFilterFiles)
                }
            return (filter, label)
        }
    }

    // 그림은 미리보기의 그림 보기에서, 위젯은 노트와 같은 격리된 페이지에서, 나머지는 QuickLook에서 본다.
    func viewLarge(_ asset: NoteAsset) {
        switch asset.kind {
        case .figure, .widget: viewing = asset
        case .image, .file: quickLook = fileURL(asset)
        }
    }

    // 그림 보기는 노트 미리보기를 그대로 쓰므로 그림 하나만 든 노트를 그린다.
    func figureText(_ asset: NoteAsset) -> String? {
        guard case .file(let name) = asset.ref, let url = files[name] else { return nil }
        return editor.assetLink(url)
    }
}
