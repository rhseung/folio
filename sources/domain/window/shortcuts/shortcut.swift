import Foundation

public struct Shortcut: Hashable, Sendable {
    // 단축키가 듣는 자리다. 안쪽 자리에 있으면 바깥 자리의 키도 함께 듣는다. 노트 편집은 노트 화면 안이면서 글 칸 안이다.
    public enum Scope: String, CaseIterable, Hashable, Sendable {
        case app, text, note, noteEditing, texEditing, materialView
        // 풀기 화면, 카드 넘기기 시트, 노트 옆 카드 칸이다. 글자 키를 수식 키 없이 쓰므로 글을 쓰는 칸이 열려 있지 않을 때만 듣는다.
        // 참거짓 카드의 참과 거짓은 문제의 참·거짓과 같은 명령(`solveTrue`, `solveFalse`)이다. 한 자리의 같은 키는 한 명령이어야 한다.
        case study

        public var within: Set<Scope> {
            switch self {
            case .app: []
            case .text, .note, .materialView, .study: [.app]
            case .noteEditing: [.app, .text, .note]
            case .texEditing: [.app, .text]
            }
        }

        // 한 자리가 다른 자리 안에 있을 때만 두 키가 함께 듣는다. 노트 편집과 TeX 편집은 함께 열리지 않는다.
        public func overlaps(_ other: Scope) -> Bool { self == other || within.contains(other) || other.within.contains(self) }

        public var isText: Bool { self == .text || within.contains(.text) }
    }

    // 관례 키는 어느 앱에서나 뜻이 같아 사용자가 바꾸지 않는다.
    public enum Kind: Hashable, Sendable {
        case changeable, fixed
    }

    public enum Group: String, CaseIterable, Hashable, Sendable {
        case navigation, tabs, window, notes, materials, study, app
    }

    public struct Binding: Hashable, Sendable {
        public var combo: KeyCombo
        // 글 칸에 포커스가 있으면 글 칸이 먼저 받는다. ⌘←·⌘→는 글 칸에서 줄 처음·끝이고 그 밖에서는 뒤로·앞으로다.
        public var yieldsToText: Bool

        public init(_ combo: KeyCombo, yieldsToText: Bool = false) {
            self.combo = combo
            self.yieldsToText = yieldsToText
        }
    }

    public var id: ShortcutID
    public var group: Group
    public var scope: Scope
    public var kind: Kind
    public var bindings: [Binding]

    public init(_ id: ShortcutID, _ group: Group, _ scope: Scope = .app, _ kind: Kind = .changeable, keys: [Binding]) {
        self.id = id
        self.group = group
        self.scope = scope
        self.kind = kind
        self.bindings = keys
    }

    // 메뉴 항목에 보이는 키다. 나머지 키는 같은 명령을 부르는 다른 길이다.
    public var key: KeyCombo? { bindings.first?.combo }

    public var name: String {
        switch id {
        case .back: String(localized: .shortcutBack)
        case .forward: String(localized: .shortcutForward)
        case .nextTab: String(localized: .shortcutNextTab)
        case .previousTab: String(localized: .shortcutPreviousTab)
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8: String(localized: .shortcutTabNumber(id.tabNumber ?? 0))
        case .lastTab: String(localized: .shortcutLastTab)
        case .newTab: String(localized: .shortcutNewTab)
        case .closeTab: String(localized: .shortcutCloseTab)
        case .closeWindow: String(localized: .shortcutCloseWindow)
        case .search: String(localized: .shortcutSearch)
        case .settings: String(localized: .shortcutSettings)
        case .inputGuide: String(localized: .shortcutInputGuide)
        case .toggleSidebar: String(localized: .shortcutToggleSidebar)
        case .toggleColumn: String(localized: .shortcutToggleColumn)
        case .noteViewToggle: String(localized: .shortcutNoteViewToggle)
        case .noteBold: String(localized: .shortcutNoteBold)
        case .noteItalic: String(localized: .shortcutNoteItalic)
        case .texBuild: String(localized: .shortcutTexBuild)
        case .lineStart: String(localized: .shortcutLineStart)
        case .lineEnd: String(localized: .shortcutLineEnd)
        case .zoomIn: String(localized: .shortcutZoomIn)
        case .zoomOut: String(localized: .shortcutZoomOut)
        case .zoomFit: String(localized: .shortcutZoomFit)
        case .solveGo: String(localized: .shortcutSolveGo)
        case .solveTrue: String(localized: .shortcutSolveTrue)
        case .solveFalse: String(localized: .shortcutSolveFalse)
        case .solveChoice: String(localized: .shortcutSolveChoice)
        case .cardFlip: String(localized: .shortcutCardFlip)
        case .cardUnknown: String(localized: .shortcutCardUnknown)
        case .cardKnown: String(localized: .shortcutCardKnown)
        }
    }
}
