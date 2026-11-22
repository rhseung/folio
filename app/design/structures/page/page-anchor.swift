import SwiftUI

// 페이지가 스크롤해 갈 자리다. 같은 자리로 다시 가라고 할 때도 `.task(id:)`가 돌도록 매번 새 토큰을 단다.
struct PageAnchor: Equatable {
    let id: AnyHashable
    let animated: Bool
    private let token = UUID()

    init(_ id: some Hashable, animated: Bool = true) {
        self.id = AnyHashable(id)
        self.animated = animated
    }
}
