import FolioDomain
import SwiftUI

// 이 앱 버전이 모르는 키도 파일에 남는다.
struct CatalogEditing<Content: View>: View {
    @Environment(Workspace.self) private var workspace
    @State private var catalog = Catalog()
    @State private var loaded = false
    @ViewBuilder let content: (Binding<Catalog>) -> Content

    var body: some View {
        content($catalog)
            .onAppear {
                catalog = workspace.catalog
                loaded = true
            }
            // 다른 페이지나 설정 창이 저장하면 그 값에서 다시 시작한다. 그러지 않으면 다음 저장이 그 변경을 되돌린다.
            .onChange(of: workspace.catalog) { _, new in catalog = new }
            .task(id: catalog) {
                guard loaded else { return }
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, catalog != workspace.catalog else { return }
                workspace.saveCatalog(catalog)
            }
            // 변경 직후에 닫으면 위의 대기가 취소되므로 남은 것을 저장한다.
            .onDisappear { if loaded, catalog != workspace.catalog { workspace.saveCatalog(catalog) } }
    }
}
