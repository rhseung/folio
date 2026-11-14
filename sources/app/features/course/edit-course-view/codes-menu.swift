import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct CodesMenu: View {
    @Environment(Workspace.self) private var workspace
    @Binding var codes: [UUID]

    var body: some View {
        let all = workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
        SearchMultiSelect(
            selection: $codes, options: all.map { PickOption(id: $0.id, title: "\($0.prefix) · \($0.department)", detail: $0.program) },
            summary: codes.isEmpty ? nil : codes.compactMap { id in all.first { $0.id == id }?.prefix }.joined(separator: " · "))
    }
}
