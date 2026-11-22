import Foundation

// 화면이 자기를 연 곳으로 돌아가는 동작이다. 칸의 기록에서 한 걸음 뒤로 가고, 뒤로 갈 곳이 없으면 false를 돌려준다.
struct GoBackAction {
    var handler: @MainActor () -> Bool = { false }

    @MainActor @discardableResult func callAsFunction() -> Bool { handler() }
}
