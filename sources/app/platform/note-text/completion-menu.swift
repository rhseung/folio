import FolioDomain
import FolioMarkdown
import SwiftUI

@MainActor @Observable final class CompletionMenu {
    private(set) var query: CompletionQuery?
    private(set) var items: [CompletionItem] = []
    var selected = 0
    @ObservationIgnored var more: (@MainActor (CompletionQuery) async -> [CompletionItem])?
    @ObservationIgnored var arrived: () -> Void = {}
    @ObservationIgnored private var pending: Task<Void, Never>?

    var visible: Bool { query != nil && !items.isEmpty }
    var current: CompletionItem? { items.indices.contains(selected) ? items[selected] : nil }

    func show(_ query: CompletionQuery, _ items: [CompletionItem]) {
        let same = self.query.map { query.continues($0) } ?? false
        let picked = same ? current?.id : nil
        let waits = items.isEmpty && more != nil && Self.late(query)

        self.query = query
        if !(waits && same) {
            self.items = items
            selected = picked.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        }

        pending?.cancel()
        guard let more, Self.late(query) else { return }
        pending = Task { [weak self] in
            let extra = await more(query)
            guard !Task.isCancelled, let self, self.query == query else { return }
            let picked = self.current?.id
            self.items = items + extra
            self.selected = picked.flatMap { id in self.items.firstIndex { $0.id == id } } ?? 0
            self.arrived()
        }
    }

    static func late(_ query: CompletionQuery?) -> Bool {
        if case .link = query?.kind { true } else { false }
    }

    func hide() {
        pending?.cancel()
        query = nil
        items = []
        selected = 0
    }

    func move(_ by: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + by + items.count) % items.count
    }
}
