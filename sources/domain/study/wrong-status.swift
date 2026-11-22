import FolioCore
import Foundation

public enum WrongStatus: Equatable, Sendable {
    // 아직 풀거나 넘기지 않았다.
    case untried
    // 틀린 적이 없다.
    case neverWrong
    // 오답이다. `since`는 마지막으로 틀린 공부일이다.
    case open(since: LocalDate)
    // 틀린 공부일에 다시 맞혔다. 다음 공부일에 맞혀야 빠진다.
    case recheck(since: LocalDate)
    // 틀린 공부일보다 뒤의 공부일에 맞혀 오답에서 빠졌다.
    case resolved(on: LocalDate)

    public var isOpen: Bool { if case .open = self { true } else { false } }
    public var isRecheck: Bool { if case .recheck = self { true } else { false } }
    // 오답 거르기와 계획의 오답 항목이 함께 보는 상태다.
    public var needsWork: Bool { isOpen || isRecheck }
}
