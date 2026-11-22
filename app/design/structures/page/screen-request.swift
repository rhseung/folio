import FolioDomain
import SwiftUI

// 연 화면 안의 상태를 바깥에서 정하는 요청이다. 어느 화면을 열지는 링크(`AppLink`)가, 창이 띄울 시트는 시트 요청(`ItemSheet`)이
// 말하고, 이 값은 그 화면 안에서 무엇을 펼치고 고르고 칠지를 말한다. 창이 `\.screenRequests`로 내려 주고 화면은 자기가 아는
// 요청에만 답한다. 창 스냅숏과 화면 맞춤 검사가 이 값으로 화면을 원하는 상태에 둔다.
enum ScreenRequest: Hashable, Sendable {
    case column
    case quickAdd(QuickAddRequest)
    case quickAddPopover
    case search(String)
    case claude
    case strip(StripStep)
    case splitEdit(SplitEdit)
    case askPage
    case viewMode(NoteViewMode)
    case outlinePopover
    case mathPalette
    case expand(UUID)
    case assets(expanded: Bool)

    struct QuickAddRequest: Hashable, Sendable {
        var text: String?
        var course: UUID?
        var due = false
        var repeats = false
    }

    struct SplitEdit: Hashable, Sendable {
        let section: Int
        let page: Int
    }

    enum StripStep: Hashable, Sendable {
        case page(Int)
        case edit(Int, Int)
        case range(Int, Int)
        case choose
        case save
        case remove(Int)
    }
}

extension Set<ScreenRequest> {
    var quickAdd: ScreenRequest.QuickAddRequest? {
        lazy.compactMap { if case .quickAdd(let r) = $0 { r } else { nil } }.first
    }

    var search: String? {
        lazy.compactMap { if case .search(let q) = $0 { q } else { nil } }.first
    }

    var strip: ScreenRequest.StripStep? {
        lazy.compactMap { if case .strip(let s) = $0 { s } else { nil } }.first
    }

    var splitEdit: ScreenRequest.SplitEdit? {
        lazy.compactMap { if case .splitEdit(let e) = $0 { e } else { nil } }.first
    }

    var viewMode: NoteViewMode? {
        lazy.compactMap { if case .viewMode(let m) = $0 { m } else { nil } }.first
    }

    var expanded: UUID? {
        lazy.compactMap { if case .expand(let id) = $0 { id } else { nil } }.first
    }

    var assets: Bool? {
        lazy.compactMap { if case .assets(let expanded) = $0 { expanded } else { nil } }.first
    }
}

extension EnvironmentValues {
    @Entry var screenRequests: Set<ScreenRequest> = []
}
