import Foundation

public struct TabStrip<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var tabs: [ID]
    public private(set) var selected: ID
    // 뒤에서 연 탭이 이어 설 자리다. 사파리처럼 같은 탭에서 ⌘-클릭으로 연 탭들은 연 순서대로 그 탭 뒤에 줄 선다.
    private var behindFrom: ID?
    private var behindLast: ID?

    public init(_ first: ID) {
        tabs = [first]
        selected = first
    }

    public init?(tabs: [ID], selected: ID) {
        guard tabs.contains(selected), Set(tabs).count == tabs.count else { return nil }
        self.tabs = tabs
        self.selected = selected
    }

    public var selectedIndex: Int { tabs.firstIndex(of: selected) ?? 0 }

    public mutating func open(_ id: ID, afterSelected: Bool = false) {
        guard !tabs.contains(id) else { return select(id) }
        tabs.insert(id, at: afterSelected ? selectedIndex + 1 : tabs.count)
        selected = id
    }

    public mutating func openBehind(_ id: ID) {
        guard !tabs.contains(id) else { return }
        let after = behindFrom == selected ? behindLast.flatMap { tabs.firstIndex(of: $0) } : nil
        tabs.insert(id, at: (after ?? selectedIndex) + 1)
        behindFrom = selected
        behindLast = id
    }

    public mutating func select(_ id: ID) {
        if tabs.contains(id) { selected = id }
    }

    public mutating func select(number n: Int) {
        if n == 9, let last = tabs.last { return selected = last }
        if tabs.indices.contains(n - 1) { selected = tabs[n - 1] }
    }

    public mutating func selectNext() { selected = tabs[(selectedIndex + 1) % tabs.count] }
    public mutating func selectPrevious() { selected = tabs[(selectedIndex + tabs.count - 1) % tabs.count] }

    @discardableResult
    public mutating func close(_ id: ID) -> Bool {
        guard tabs.count > 1, let i = tabs.firstIndex(of: id) else { return false }
        tabs.remove(at: i)
        if selected == id { selected = tabs[min(i, tabs.count - 1)] }
        return true
    }

    public mutating func closeOthers(than id: ID) {
        guard tabs.contains(id) else { return }
        tabs = [id]
        selected = id
    }

    public mutating func move(_ id: ID, to index: Int) {
        guard let i = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: i)
        tabs.insert(id, at: max(0, min(index, tabs.count)))
    }
}
