import Foundation

extension Array where Element: ItemCommand {
    // 같은 그룹 안에서는 선언한 순서를 지킨다.
    public func inMenuOrder() -> [Element] {
        enumerated().sorted { ($0.element.group, $0.offset) < ($1.element.group, $1.offset) }.map(\.element)
    }
}
