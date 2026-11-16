import Foundation

// 링크와 항목을 누를 때 함께 누른 키가 여는 자리를 정한다. 사파리처럼 어느 화면에서나 같은 뜻이다.
public enum LinkClick: Hashable, Sendable {
    case here, tabBehind, tab, beside

    public init(_ modifiers: KeyCombo.Modifiers) {
        let held = modifiers.intersection([.command, .shift, .option])
        switch held {
        case [.command]: self = .tabBehind
        case [.command, .shift]: self = .tab
        case [.command, .option]: self = .beside
        default: self = .here
        }
    }
}
