import FolioDomain
import FolioStorage
import WebKit

// frame 크기를 따르는 페이지(`100vh`, `50vh`, `calc(600px - 100vh)`)는 frame이 바뀔 때마다 같은 비율로 바뀌므로, 따라가면 끝나지 않는다. 그런 페이지는 처음 보인 높이를
// 유지한다. frame이 따라가는 동안 다시 커지는 내용(글꼴, 그림, 한 프레임 늦게 그린 차트)은 제 나름의 양만큼 바뀌므로, 둘이 한 번 함께 바뀐 것만으로는 구분할 수 없다.
struct WidgetSizer {
    private(set) var height: CGFloat?
    private var last: (page: Double, view: Double)?
    private var start: Double?
    private var share: Double?
    private var followsView = false

    mutating func report(page: Double, view: Double) -> CGFloat? {
        guard view >= 1, !followsView else { return nil }
        defer { last = (page, view) }
        let start = start ?? view
        self.start = start
        if let last, abs(view - last.view) >= 0.5 {
            if abs(page - last.page) >= 0.5 {
                let share = (page - last.page) / (view - last.view)
                if let previous = self.share, abs(share - previous) < 0.01 {
                    followsView = true
                    return fit(start)
                }
                self.share = share
            } else {
                share = nil
            }
        }
        return fit(page)
    }

    private mutating func fit(_ page: Double) -> CGFloat? {
        let fitted = max(CGFloat(page).rounded(.up), 16)
        guard fitted != height else { return nil }
        height = fitted
        return fitted
    }
}
