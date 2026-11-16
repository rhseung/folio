import FolioDomain
import SwiftUI

// 폭의 animation이 아니다. animation을 쓰면 칸마다 화면이 자기 새 배치도 animation 했고, 지연 페이지(과목 개요)는 행과
// scroll offset이 흔들리며 튀었다. 넓어지는 칸은 화면을 바로 끝 폭으로 배치해 옆 칸을 덮었다. 그래서 구분선 drag처럼
// 단계를 밟아, frame마다 열린 칸의 화면을 그 frame의 폭으로 배치하고 안쪽은 animation 하지 않는다. 접히거나 열리는 칸은
// 화면을 열린 폭으로 두고 패널의 가장자리만 그 위로 움직인다.
struct PaneGlide: Equatable {
    static let duration = 0.5
    static let spring = Theme.Motion.paneSpring

    let from: PaneLayout
    let fold: PaneLayout.Fold
    let start = Date()
    private let id = UUID()

    init(from: PaneLayout, fold: PaneLayout.Fold) {
        self.from = from
        self.fold = fold
    }

    func progress(at date: Date) -> Double {
        let t = date.timeIntervalSince(start)
        return t >= Self.duration ? 1 : min(1, max(0, Self.spring.value(target: 1.0, time: t)))
    }
}
