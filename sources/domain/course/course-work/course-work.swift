import Foundation

extension CourseFile {
    public mutating func continueRepeating(_ id: UUID, until end: Date?, calendar: Calendar, device: DeviceID, now: Date) {
        guard let a = assignments.first(where: { $0.id == id }), let rule = a.repeats, !a.status.isOpen, let due = a.due,
            !assignments.contains(where: { $0.title == a.title && ($0.due ?? .distantPast) > due })
        else { return }
        let next = nextDue(after: due, rule: rule, title: a.title, calendar: calendar)
        guard end.map({ next <= $0 }) ?? true else { return }

        var made = Assignment(device: device, at: now, title: a.title, due: next)
        made.repeats = rule
        made.componentId = a.componentId
        made.componentGroup = a.componentGroup
        assignments.append(made)
    }

    // 월 반복은 처음 시작한 날을 지킨다. 그래서 짧은 달의 말일로 당겨진 마감도 다음 달에는 31일로 돌아간다.
    public func nextDue(after due: Date, rule: AssignmentRepeat, title: String, calendar: Calendar) -> Date {
        let first = (assignments.filter { $0.title == title && $0.repeats?.unit == .month }.compactMap(\.due) + [due]).min()!
        return rule.next(after: due, day: calendar.component(.day, from: first), calendar: calendar)
    }
}
