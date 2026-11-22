import Foundation

public enum ShortcutID: String, CaseIterable, Hashable, Sendable {
    case back, forward
    case nextTab, previousTab, tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8, lastTab
    case newTab, closeTab, closeWindow
    case search, settings, inputGuide
    case toggleSidebar, toggleColumn
    case noteViewToggle, noteBold, noteItalic
    case texBuild
    case lineStart, lineEnd
    case zoomIn, zoomOut, zoomFit
    case solveGo, solveTrue, solveFalse, solveChoice
    case cardFlip, cardUnknown, cardKnown

    // ⌘1~⌘8은 그 번호의 탭이다. ⌘9는 사파리처럼 몇 번째든 마지막 탭이다.
    public static func tab(number n: Int) -> ShortcutID? {
        let numbered: [ShortcutID] = [.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8]
        return n == 9 ? .lastTab : numbered.indices.contains(n - 1) ? numbered[n - 1] : nil
    }

    public var tabNumber: Int? {
        switch self {
        case .tab1: 1
        case .tab2: 2
        case .tab3: 3
        case .tab4: 4
        case .tab5: 5
        case .tab6: 6
        case .tab7: 7
        case .tab8: 8
        case .lastTab: 9
        default: nil
        }
    }
}
