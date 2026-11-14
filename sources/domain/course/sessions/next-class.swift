import Foundation

extension CourseFile {
    // 이미 열린 수업이다. 휴강은 열리지 않았으므로 뺀다.
    public func heldSessions(at now: Date) -> [Session] { sessions.filter { $0.date <= now && !$0.isCancelled } }

    // 만든 회차와 시간표가 제안한 수업 중 가장 가까운 것이다. 제안한 수업은 아직 회차가 없어 `session`이 nil이다.
    public func nextClass(after now: Date, suggested: [Date]) -> (date: Date, session: Session?)? {
        let made = sessions.filter { $0.date > now && !$0.isCancelled }.map { (date: $0.date, session: Optional($0)) }
        let planned = suggested.filter { $0 > now }.map { (date: $0, session: Session?.none) }
        return (made + planned).min { $0.date < $1.date }
    }
}
