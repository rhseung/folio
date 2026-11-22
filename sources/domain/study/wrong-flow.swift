import FolioCore
import Foundation

// 문제와 카드가 함께 쓰는 오답 규칙이다(#573 "오답에서 빠지는 법"). 해설을 본 직후 맞히는 것은 기억해 낸 것이 아니므로,
// 틀린 공부일보다 뒤의 공부일에 맞혀야 오답에서 빠진다.
public enum WrongFlow {
    // `right`가 false면 틀림(문제의 틀림과 부분, 카드의 모름)이다. 순서는 시각 순이어야 한다.
    public static func status(_ tries: [(day: LocalDate, right: Bool)]) -> WrongStatus {
        var status = WrongStatus.untried
        for (day, right) in tries {
            switch (status, right) {
            case (_, false): status = .open(since: day)
            case (.untried, true): status = .neverWrong
            case (.open(let since), true), (.recheck(let since), true):
                status = day > since ? .resolved(on: day) : .recheck(since: since)
            default: break
            }
        }
        return status
    }
}
