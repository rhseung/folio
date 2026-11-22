import FolioCore
import Foundation

// 문제와 카드가 함께 쓰는 오답 규칙이다(#573 "오답에서 빠지는 법"). 해설을 본 직후 맞히는 것은 기억해 낸 것이 아니므로,
// 틀린 공부일보다 뒤의 공부일에 맞혀야 오답에서 빠진다.
public enum WrongFlow {
    // `right`가 false면 틀림(문제의 틀림과 부분, 카드의 모름)이다. 순서는 시각 순이어야 한다.
    public static func status(_ tries: [(day: LocalDate, right: Bool)]) -> WrongStatus {
        tries.reduce(WrongStatus.untried) { next($0, day: $1.day, right: $1.right) }
    }

    public static func next(_ status: WrongStatus, day: LocalDate, right: Bool) -> WrongStatus {
        switch (status, right) {
        case (_, false): .open(since: day)
        case (.untried, true): .neverWrong
        case (.open(let since), true), (.recheck(let since), true):
            if day > since { .resolved(on: day) } else { .recheck(since: since) }
        default: status
        }
    }

    // 맞혔는데도 오답에서 빠지지 않는 경우다. 풀기 화면은 이때 다음 공부일에 다시 맞혀야 한다고 알린다.
    public static func staysRecheck(_ status: WrongStatus, rightOn day: LocalDate) -> Bool {
        next(status, day: day, right: true).isRecheck
    }
}
