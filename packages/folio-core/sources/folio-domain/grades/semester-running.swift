import Foundation

extension Semester {
    /// From the first day through the last, both included. A term missing either date, or with them reversed, never runs.
    public func isRunning(on day: LocalDate) -> Bool {
        guard let start, let end else { return false }
        return start <= day && day <= end
    }
}
